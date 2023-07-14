#Requires -Modules "Az.Resources","Az.ConnectedMachine"
<#
.DESCRIPTION
   This Script can be used to update Azure Arc extensions to a specific version. A Csv that contains a list of ResourceIds
   of the afected machines is generated after every execution.
   The Script select automatically all the Azure Arc machines in the tenant that have a extension with a version lower than 
   the Desired one.

   ONLY machines with Tag  {"EnableExtensionsUpate": "True"} with be updated by default. Skip this filter using SKipTags parameter
.PARAMETER type
    Specifies Extension Type
.PARAMETER PublisherName
    Specifies Extension PublisherName
.PARAMETER DesiredVersion
    Specifies Extension version to be installed
.PARAMETER Location
    Specifies Extension location
.PARAMETER WhatIf
    No update is performed. A preview list of the posible affected machines is shown
.PARAMETER SkipTags
    Removes the Tag filter. Every machine that have the extension version lower than the desired one is affected
.EXAMPLE
   This updates machines with tag {"EnableExtensionsUpate": "True"} to version 1.5.66 of WindowsPatchExtension
   .\Update-AzureArcExtensions.ps1 -PublisherName Microsoft.CPlat.Core -Type WindowsPatchExtension -DesiredVersion 1.5.66 -Location eastus 
.EXAMPLE
   This updates machines to version 1.5.66 of WindowsPatchExtension, regarding its tags
   .\Update-AzureArcExtensions.ps1 -PublisherName Microsoft.CPlat.Core -Type WindowsPatchExtension -DesiredVersion 1.5.66 -Location eastus -SkipTags
.EXAMPLE
   This previews machines with tag {"EnableExtensionsUpate": "True"} that have version lower than 1.5.66 of WindowsPatchExtension
   .\Update-AzureArcExtensions.ps1 -PublisherName Microsoft.CPlat.Core -Type WindowsPatchExtension -DesiredVersion 1.5.66 -Location eastus -WhatIf

#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [ValidateSet("AdminCenter", "AzureMonitorLinuxAgent", "AzureMonitorWindowsAgent", "AzureSecurityLinuxAgent", "AzureSecurityWindowsAgent", "ChangeTracking-Linux", "ChangeTracking-Windows", "CustomScript", "CustomScriptExtension", "DependencyAgentLinux", "DependencyAgentWindows", "LinuxAgent.SqlServer", "LinuxOsUpdateExtension", "LinuxPatchExtension", "MDE.Linux", "MDE.Windows", "WindowsAgent.SqlServer", "WindowsOsUpdateExtension", "WindowsPatchExtension")]
    [string]$Type,
    [Parameter(Mandatory)]
    [ValidateSet("Microsoft.AdminCenter", "Microsoft.Azure.ActiveDirectory", "Microsoft.Azure.Automation.HybridWorker", "Microsoft.Azure.AzureDefenderForServers", "Microsoft.Azure.Extensions", "Microsoft.Azure.Monitor", "Microsoft.Azure.Monitoring.DependencyAgent", "Microsoft.AzureData", "Microsoft.Compute", "Microsoft.CPlat.Core", "Microsoft.EnterpriseCloud.Monitoring", "Microsoft.SoftwareUpdateManagement")]
    [string]$PublisherName,
    [Parameter(Mandatory)]
    $DesiredVersion,
    $Location = "eastus",
    [switch]$Whatif,
    [switch]$SkipTags 
)


#################
# GLOBAL THINGS #
#################

#Tag Definition
$TagName = "EnableExtensionsUpdate"
$TagValue = "True"

#Check Script Input Data

try {
    Get-AzVMExtensionImage -Location $Location -PublisherName $PublisherName -Type $Type -Version $DesiredVersion -ErrorAction Stop | Out-Null
    $Extensionversions = Get-AzVMExtensionImage -Location $Location -PublisherName $PublisherName -Type $Type -ErrorAction Stop 
    $HighestVersion = ($Extensionversions | Select-Object @{N = "Version"; E = { [version]$_.Version } } | Sort-Object -Property Version  | Select-Object -ExpandProperty Version -Last 1).tostring()
    if ([version]$DesiredVersion -lt [Version]$HighestVersion) {
        Write-host "Version $DesiredVersion is not the highest one for this type, the highgtest version for this type is $HighestVersion" -ForegroundColor Green
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
The query selects the Azure Arc Machines that have a lower extension version than the Desired, the extension is in a Succeeded state and the Arc Machine
is in a Connected state#>

Write-Host "Querying existing resources ... " -ForegroundColor Green


$kqlQuery = @"
resources
| where type == 'microsoft.hybridcompute/machines/extensions'
| where properties.type == '$type' and location == '$Location'
| where properties.provisioningState == "Succeeded"
| extend typeHandlerVersion = tostring(properties.typeHandlerVersion)
| where parse_version(typeHandlerVersion) < parse_version('$DesiredVersion')
| extend machineid = tolower(tostring(split(id,'/extensions/',0)[0]))
| join kind=inner (resources
| where type in ('microsoft.hybridcompute/machines') and properties.status == "Connected"
"@

if (-not ($PSBoundParameters.ContainsKey("SkipTags"))) {
    $kqlQuery += "`n| where tags['$TagName'] == '$TagValue'"
}
$kqlQuery += "`n| project machineid = tolower(id)) on machineid"


$kqlQueryResults = Search-AzGraph -Query $kqlQuery -First 1000

if ($kqlQueryResults.count -eq 0)
{ Write-Host "No Azure Arc Machine meet the criteria to update" -ForegroundColor Yellow; break }

$ExtensiontoUpdate = $kqlQueryResults | Select-Object @{N = "subscription"; E = { ($_.id -split "/")[2] } }, resourceGroup, @{N = "Machine"; E = { ($_.id -split "/")[-3] } }, @{N = "Type"; E = { ($_.id -split "/")[-5] } }, Name, Location, TypeHandlerVersion


Write-Host "$($ExtensiontoUpdate.count) Machine(s) will be affected for the update.." -ForegroundColor Yellow
# Query finished, showing results
$ExtensiontoUpdate | Format-Table

if ($Whatif) {

    #Loging machines to CSV
    $csvPath = "$(Get-Date -f {yyyyMMddhhmmss})-WhatIf-$type-$location-$DesiredVersion.csv"
    "ResourceId" | Out-File -FilePath $csvPath

    foreach ($extension in $ExtensiontoUpdate) {
        "/subscriptions/$($extension.subscription)/resourceGroups/$($extension.resourceGroup)/providers/Microsoft.HybridCompute/machines/$($extension.Machine)" | Out-File -FilePath $csvPath -Append        
    }
    
    Write-Host "Whatif parameter was passed. Skipping update.." -ForegroundColor Yellow; break 
}
else {
    # Perform the Update
    Read-Host -Prompt "Listed machine's extensions will be updated. Press ENTER to continue"
    Write-Host "Performing the update..." -ForegroundColor Green
   
    $ExtensiontoUpdateGrouped = $ExtensiontoUpdate | Group-Object -Property subscription
    $UpdateOperations = foreach ($group in $ExtensiontoUpdateGrouped) {
        #Get-AzSubscription -SubscriptionId $group.Name -WarningAction SilentlyContinue
        $Subscription = Select-AzSubscription -SubscriptionId $group.Name -WarningAction SilentlyContinue
        Write-Host "Update extensions from Subscription: $($Subscription.Subscription.Name) $($Subscription.Subscription.id)" -ForegroundColor Green
        foreach ($extension in $group.Group ) {
            
            Update-AzConnectedExtension -MachineName $extension.machine `
                -ResourceGroupName $extension.resourceGroup `
                -ExtensionTarget @{"$($PublisherName).$($type)" = @{"targetVersion" = $DesiredVersion } } `
                -NoWait -Verbose
        }
    } 

    #Loging machines to CSV
    $csvPath = "$(Get-Date -f {yyyyMMddhhmmss})-Updated-$type-$location-$DesiredVersion.csv"
    "ResourceId" | Out-File -FilePath $csvPath
  
    foreach ($extension in $ExtensiontoUpdate) {
        "/subscriptions/$($extension.subscription)/resourceGroups/$($extension.resourceGroup)/providers/Microsoft.HybridCompute/machines/$($extension.Machine)" | Out-File -FilePath $csvPath -Append        
    }

    $UpdateOperations
    #https://management.azure.com/subscriptions/df77550b-74e4-4b51-a312-a1116f915de8/providers/Microsoft.HybridCompute/locations/westeurope/operationstatus/548bcefb-d11b-4d34-af26-e5958168f8f8?api-version=2022-03-10

    Write-Host "CSV file '$csvPath' with ResourceIds of the affected machines was created. Check the update in the Azure Portal" -ForegroundColor Green

}
break
