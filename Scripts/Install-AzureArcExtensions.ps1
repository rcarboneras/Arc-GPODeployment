#Requires -Modules "Az.Resources","Az.ConnectedMachine"
<#
.DESCRIPTION
   This Script can be used to install Azure Arc extensions with a specific version on Azure Arc Servers. A Csv that contains a list of ResourceIds
   of the afected machines is generated after every execution.
   The Script selecst automatically all the Azure Arc machines that are in a Connected State and that don't have the extesion allready installed.

   ONLY extensions in machines with Tag  {"EnableExtensionsInstall": "True"} will be installed by default. Skip this filter using SKipTags parameter
.PARAMETER Type
    Specifies Extension Type
.PARAMETER PublisherName
    Specifies Extension PublisherName
.PARAMETER DesiredVersion
    Specifies Extension version to be installed
.PARAMETER Location
    Specifies Extension location
.PARAMETER WhatIf
    No installation is performed. A preview list of the posible affected machines is shown
.PARAMETER SettingsFile
    Specifies a JSON file with the settings for the extension.
    {
    "proxy": {
        "mode": "application",
        "address": "http://proxy.contoso.com"
    }
}
.PARAMETER SkipTags
    Removes the Tag filter. Every machine that don't have the extension installed will be affected, regardless of its Azure tags
.EXAMPLE
   This installs Change Tracking extension version 2.20.0.0 on Windows machines in westeurope location, regardless its tags
   .\Install-AzureArcExtensions.ps1 -PublisherName Microsoft.Azure.ChangeTrackingAndInventory -Type ChangeTracking-Windows -OSType windows -DesiredVersion 2.20.0.0 -Location westeurope -skipTags
.EXAMPLE
   This install WindowsPatchExtension version 1.5.66 to machines, with tag 'EnableExtensionsInstall' in westeurope location
   .\Install-AzureArcExtensions.ps1 -PublisherName Microsoft.CPlat.Core -Type WindowsPatchExtension -OSType windows -DesiredVersion 1.5.66 -Location westeurope
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [ValidateSet("AdminCenter", "AzureMonitorLinuxAgent", "AzureMonitorWindowsAgent", "AzureSecurityLinuxAgent", "AzureSecurityWindowsAgent", "ChangeTracking-Linux", "ChangeTracking-Windows", "CustomScript", "CustomScriptExtension", "DependencyAgentLinux", "DependencyAgentWindows", "LinuxAgent.SqlServer", "LinuxOsUpdateExtension", "LinuxPatchExtension", "MDE.Linux", "MDE.Windows", "WindowsAgent.SqlServer", "WindowsOsUpdateExtension", "WindowsPatchExtension")]
    [string]$Type,
    [Parameter(Mandatory)]
    [ValidateSet("Microsoft.AdminCenter", "Microsoft.Azure.ActiveDirectory", "Microsoft.Azure.Automation.HybridWorker", "Microsoft.Azure.AzureDefenderForServers", "Microsoft.Azure.ChangeTrackingAndInventory", "Microsoft.Azure.Extensions", "Microsoft.Azure.Monitor", "Microsoft.Azure.Monitoring.DependencyAgent", "Microsoft.AzureData", "Microsoft.Azure.Security.Monitoring", "Microsoft.Compute", "Microsoft.CPlat.Core", "Microsoft.EnterpriseCloud.Monitoring", "Microsoft.SoftwareUpdateManagement")]
    [string]$PublisherName,
    [Parameter(Mandatory)]
    [ValidateSet("windows", "linux")]
    [string]$OSType,
    $DesiredVersion,
    [Parameter(Mandatory)]
    $Location = "eastus",
    [switch]$Whatif,
    [switch]$SkipTags,
    [string]$SettingsFile
)


#################
# GLOBAL THINGS #
#################

#Tag Definition
$TagName = "EnableExtensionsInstall"
$TagValue = "True"



#Check Script Input Data


$ExtensionsOS = @{
    windows = @(
        "AdminCenter"
        "AzureMonitorWindowsAgent"
        "AzureSecurityWindowsAgent"
        "CustomScriptExtension"
        "ChangeTracking-Windows"
        "DependencyAgentWindows"
        "MDE.Windows"
        "WindowsAgent.SqlServer"
        "WindowsOsUpdateExtension"
        "WindowsPatchExtension"
    )
    linux   = @(
        "AzureMonitorLinuxAgent"
        "AzureSecurityLinuxAgent"
        "CustomScriptExtension"
        "ChangeTracking-Linux"
        "DependencyAgentLinux"
        "LinuxAgent.SqlServer"
        "LinuxOsUpdateExtension"
        "LinuxPatchExtension"
        "MDE.Linux"
    )
}

if ($Type -notin $ExtensionsOS.$OSType) {
    Write-Host "The extension type '$Type' is not available for OS '$OSType'" -ForegroundColor Red
    Write-Host "The available extensions for OS '$OSType' are:" -ForegroundColor Yellow
    $ExtensionsOS.$OSType | Out-Default
    break
}

try {
    Get-AzVMExtensionImage -Location $Location -PublisherName $PublisherName -Type $Type -Version $DesiredVersion -ErrorAction Stop | Out-Null
    $Extensionversions = Get-AzVMExtensionImage -Location $Location -PublisherName $PublisherName -Type $Type -ErrorAction Stop 
    $HighestVersion = ($Extensionversions | Select-Object @{N = "Version"; E = { [version]$_.Version } } | Sort-Object -Property Version  | Select-Object -ExpandProperty Version -Last 1).tostring()
    if ([version]$DesiredVersion -lt [Version]$HighestVersion) {
        Write-host "Version $DesiredVersion is not the highest one for this type, the hightest version for this type is $HighestVersion" -ForegroundColor Green
        $Continue = Read-Host -Prompt "Do you want to continue(Y/N)"
        if ($Continue -ne "y") { break }
        Write-Host "(Y) pressed, continuing..." -ForegroundColor Green

    }
    elseif ([version]$DesiredVersion -gt [Version]$HighestVersion) {
        Write-host "Version $DesiredVersion is higher than the highest available version for this type in $location, witch is $HighestVersion"
        break 
    }
}
catch {
    Write-Host "We could not find the extension type in the given location. Please check the error message bellow" -ForegroundColor Red
    Write-Host "PublisherName: $PublisherName`nType: $Type`nVersion: $DesiredVersion`nLocation: $Location`n" -ForegroundColor Yellow
    $Extensionversions = Get-AzVMExtensionImage -Location $Location -PublisherName $PublisherName -Type $Type -ErrorAction SilentlyContinue |  Select-Object PublisherName, Type, @{N = "Version"; E = { [version]$_.Version } }, Location | Sort-Object -Property Version | Select-Object -Last 5
    if ($null -ne $Extensionversions) {
        Write-host "The following are the latest 5 versions available for this extension type" -ForegroundColor Green
        $Extensionversions | Out-Default
    }
    $_; break 
}

<#Querying existing resources
The folowing query selects the Azure Arc Machines that are connected and don't have the desired extension already installed#>

Write-Host "Querying existing resources ... " -ForegroundColor Green
Write-Host "Querying machines in location '$location' and OS '$OSType' that has no '$Type' extension ... " -ForegroundColor Green

$kqlQueryServersWithoutExtension = @"
resources
| where type in ('microsoft.hybridcompute/machines','microsoft.compute/virtualmachines')
| where location == '$location'
| extend
    JoinID = toupper(id),
    OSType = iff( type  == 'microsoft.hybridcompute/machines', tostring(properties.osType), tolower(tostring((properties.storageProfile).osDisk.osType))),
    ServerStatus = iff( type  == 'microsoft.hybridcompute/machines', tostring(properties.status), tostring((properties.extended.instanceView).powerState.displayStatus))
| where ServerStatus in ('Connected')
| join kind=leftouter(
    resources
| where type == 'microsoft.hybridcompute/machines/extensions' or type == 'microsoft.compute/virtualmachines/extensions'
| where properties.type in ('$type') and location == '$location'
| extend
        VMId = toupper(substring(id, 0, indexof(id, '/extensions'))),
        ExtensionName = tostring(properties.type),
		Status = tostring (properties.provisioningState)
) on `$left.JoinID == `$right.VMId
| where OSType in ('$OSType')
| extend Serverid = id
| extend ProvisionState = pack(ExtensionName, Status)
| where isempty(Status)
"@

if (-not ($PSBoundParameters.ContainsKey("SkipTags"))) {
    $kqlQueryServersWithoutExtension += "`n| where tags['$TagName'] == '$TagValue'"
}


$kqlQueryResults = Search-AzGraph -Query $kqlQueryServersWithoutExtension -First 1000


# Query finished, showing results

$ExtensiontoInstall = $kqlQueryResults | Select-Object @{N = "subscription"; E = { ($_.id -split "/")[2] } }, resourceGroup, @{N = "Machine"; E = { $_.Name } }, @{N = "type"; E = { $type } }, @{N = "version"; E = { $DesiredVersion } }, Location

Write-Host "`nThe following $($ExtensiontoInstall.Count) machines don't have extension $type in location $location.." -ForegroundColor Yellow
$ExtensiontoInstall | Format-Table


if ($Whatif) {

    #Loging machines to CSV
    $csvPath = "$(Get-Date -f {yyyyMMddhhmmss})-WhatIf-$type-$location-$DesiredVersion.csv"
    "ResourceId" | Out-File -FilePath $csvPath

    foreach ($extension in $ExtensiontoInstall) {
        "/subscriptions/$($extension.subscription)/resourceGroups/$($extension.resourceGroup)/providers/Microsoft.HybridCompute/machines/$($extension.Machine)" | Out-File -FilePath $csvPath -Append        
    }
    
    Write-Host "Whatif parameter was passed. Skipping installation.." -ForegroundColor Yellow; break 
}
else {
    
    # Perform the Installation

  
    Write-Host "You are about to install $type extension for $OStype (version $DesiredVersion)  on $($ExtensiontoInstall.count) Machine(s) in $location location.." -ForegroundColor Yellow
    Read-Host -Prompt "Press ENTER to continue"
    
    Write-Host "Performing the installation..." -ForegroundColor Green
   
    $ExtensiontoInstallGrouped = $ExtensiontoInstall | Group-Object -Property subscription
    $global:InstallOperations = foreach ($group in $ExtensiontoInstallGrouped) {
        #Get-AzSubscription -SubscriptionId $group.Name -WarningAction SilentlyContinue
        $Subscription = Select-AzSubscription -SubscriptionId $group.Name -WarningAction SilentlyContinue
        Write-Host "Install extensions from Subscription: $($Subscription.Subscription.Name) $($Subscription.Subscription.id)" -ForegroundColor Green

        # Check if settings file was passed
        if ($PSBoundParameters.ContainsKey("SettingsFile")) {
            Write-Host "Settings file was passed. Checking if it exists..." -ForegroundColor Green
            if (Test-Path $SettingsFile) {
                Write-Host "Settings file exists. Reading settings..." -ForegroundColor Green
                $Settingscontent = Get-Content $SettingsFile | ConvertFrom-Json
                $Settings = @{}
                foreach ($property in $Settingscontent.PSObject.Properties) {
                    $Settings[$property.Name] = $property.Value
                }
                Write-Host "Settings file was read successfully" -ForegroundColor Green
            }
            else {
                Write-Host "Settings file does not exist. Exiting..." -ForegroundColor Yellow
                break
            }
        }

        foreach ($extension in $group.Group ) {
            $Parameters = @{
                MachineName       = $extension.machine
                Name              = $extension.type
                ResourceGroupName = $extension.resourceGroup
                Publisher         = $PublisherName
                ExtensionType     = $Type
                Location          = $Location
                NoWait            = $true
                Verbose           = $true
            }
            if ($PSBoundParameters.ContainsKey("SettingsFile")) {
                $Parameters["Setting"] = $Settings
            }
    
            New-AzConnectedMachineExtension @Parameters
        }
    } 

    #Loging machines to CSV
    $csvPath = "$(Get-Date -f {yyyyMMddhhmmss})-Installed-$type-$location-$DesiredVersion.csv"
    "ResourceId" | Out-File -FilePath $csvPath
  
    foreach ($extension in $ExtensiontoInstall) {
        "/subscriptions/$($extension.subscription)/resourceGroups/$($extension.resourceGroup)/providers/Microsoft.HybridCompute/machines/$($extension.Machine)" | Out-File -FilePath $csvPath -Append        
    }

    $InstallOperations
 
    Write-Host "CSV file '$csvPath' with ResourceIds of the affected machines was created. Check the installation in the Azure Portal" -ForegroundColor Green

}