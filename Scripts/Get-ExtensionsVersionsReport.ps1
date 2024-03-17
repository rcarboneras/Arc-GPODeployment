#Requires -Modules "Az.Resources","Az.ConnectedMachine"
# This script gets the highest and the lowest versions of current Azure Arc extensions in the environment, as well as the max extension version published
# for a given an Azure location

Param (
    $Location = "westeurope"
)

#Check the existing versions in your environment
$kqlQuery = @"
resources
| where type == 'microsoft.hybridcompute/machines/extensions'
| project Type=tostring(properties.type),PublisherName = tostring(properties.publisher),Version = tostring(properties.typeHandlerVersion),parsedversion = parse_version(tostring(properties.typeHandlerVersion))
| summarize arg_max(parsedversion,*),  arg_min(parsedversion,*)  by Type,PublisherName
| extend  ServersOutdated = iff(parsedversion1 < parsedversion,"Yes","")
| project  Type,PublisherName,CurrentMaxVersion=Version,CurrentMinVersion=Version1,ServersOutdated
"@

$CurrentVersions = Search-AzGraph -Query $kqlQuery 


# Get extension types from a Publisher
# Get-AzVMExtensionImageType -Location eastus -PublisherName Microsoft.AzureData 


# Get latest version available in location, for each of the extension
$AvailableVersions = foreach ($extension in $CurrentVersions) {
    Get-AzVMExtensionImage -Location $Location -PublisherName $extension.PublisherName -Type $extension.type | select PublisherName, Type, @{N = "Version"; E = { [version]$_.Version } }| Sort-Object -Property Version | Select-Object -Last 1
}

#Index Current versions
$CurrentVersionsHash = @{}
foreach ($obj in $CurrentVersions) {
    $CurrentVersionsHash[$obj.Type] = $obj
}


# Join arrays based on type, to find new available versions 

$result = foreach ($tempobj in $AvailableVersions) {
    $type = $tempobj.type
    if ($CurrentVersionsHash.ContainsKey($type)) {
        $newobj = $CurrentVersionsHash[$type] | Select-Object *, @{N = "AvailableVersion"; E = { $tempobj.version } }
        if ([version]$newobj.CurrentMaxVersion -lt [version]$newobj.AvailableVersion) { $UpdateAvailable = "True" }
        else { $UpdateAvailable = $null }
        $newobj | Add-Member NoteProperty UpdateAvailable -Value $UpdateAvailable
        $newobj
    }
}
$result | Format-Table