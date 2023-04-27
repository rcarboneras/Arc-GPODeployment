<#
.DESCRIPTION
    This Script parses XMLs files created by the EnableArc.ps1 onboarding script
    The information it shown in the screen and exported to the AzureArcOnboardingprerequisites.csv
    CSV file.

    XMLs files older than 24h. are automatically deleted.
#>

#Input section
$Reportfolder = "\\server\AzureArcOnboard\AzureArcLogging" # Path to the network share and folder with XMLs logs

# Main

$files = Get-ChildItem -Recurse -Filter *.xml -Path $Reportfolder -File
$files | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Verbose
$servers = $files | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-1) } `
| ForEach-Object { Import-Clixml $_.FullName }`
| Sort-Object PowershellVersion, FrameworkVersion, Computer  -Descending `
| Select-Object Computer, OSVersion, FrameworkVersion, PowerShellVersion, AzureVM, ArcCompatible


$servers  = Get-ChildItem \\arcdc\ArcLoging\ -Recurse -File | ForEach-Object {
$obj = Import-Clixml $_.FullName;

if ($obj.AgentStatus -eq "Disconnected") {$agentstatus = $obj.AgentStatus}
else {$agentstatus = "NoAgent"}

[PSCustomObject]@{
    LastWriteTime = $_.LastWriteTime
    OSVersion = $obj.OSVersion
    AzureVM = $obj.AzureVM
    Computer = $obj.Computer
    ArcCompatible = $obj.ArcCompatible
    PowershellVersion = $obj.PowershellVersion
    FrameworkVersion = $obj.FrameworkVersion
    AgentStatus = $agentstatus
    AgentInfo = $obj.AgentInfo
    AgentLastHeartbeat = $obj.AgentLastHeartbeat
    httpsProxy = $obj.httpsProxy
    AgentErrorCode = $obj.AgentInfo
    AgentErrorTimestamp = $obj.AgentErrorTimestamp
    AgentErrorDetails = $obj.AgentErrorDetails

    }
}


$servers | Where-Object { $_.AzureVM -NE "True" } | Export-Csv -Path AzureArcOnboardingInformation.csv -NoTypeInformation
Clear-Host
"Total servers found: $($servers.Count)"
$servers | Format-Table