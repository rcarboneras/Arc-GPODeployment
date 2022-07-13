<#
.DESCRIPTION
    This Runbook parses XMLs files created by the EnableArc.ps1 onboarding script
    The information is uploaded to a Log Analytics workspace for further analysis using a workbook

    NOTE: XMLs files older than 24h. are automatically deleted.
#>

$ErrorActionPreference = "Continue"



#Input section
$Reportfolder = "\\server\AzureArcOnboard\AzureArcLogging" # Path to the network share and folder with XMLs logs
#https://docs.microsoft.com/en-us/azure/azure-monitor/platform/data-collector-api

# Replace with your Workspace ID
$CustomerId = "<Workspaceid here>"  

# Replace with your Primary Key
$SharedKey = "<YourSharedkeyhere>"

# Specify the name of the record type that you'll be creating
$LogType = "ArcOnboardingStatus"


#region Function definitions


# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource) {
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId, $encodedHash
    return $authorization
}


# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType) {
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
    $headers = @{
        "Authorization"        = $signature;
        "Log-Type"             = $logType;
        "x-ms-date"            = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }
    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}
#endregion



# Main


#AzureConnection

Add-AzAccount -Identity
Select-AzSubscription -SubscriptionName "<Your Subscription name here>"
Write-Output "This runbook is running in worker: $($env:COMPUTERNAME)"

#Geting XMLs files

Write-Output "Getting XMLs files from Network shared folder $Reportfolder ..."

$files = Get-ChildItem -Recurse -Filter *.xml -Path $Reportfolder -File

Write-Output "Got information from $($files.count) servers"

#Delete older files (+24h)
$files | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Verbose

#Import XML files
$servers = $files | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-1) } | ForEach-Object {
    $obj = Import-Clixml $_.FullName -ErrorAction SilentlyContinue -ErrorVariable ImportErrors;

    if ($obj.AgentStatus -eq "Disconnected") { $agentstatus = $obj.AgentStatus }
    else { $agentstatus = "NoAgent" }

    [PSCustomObject]@{
        LastWriteTime       = Get-Date ($_.LastWriteTimeUtc) -Format "yyyy-MM-ddTHH:mm:ssZ"
        OSVersion           = $obj.OSVersion
        AzureVM             = $obj.AzureVM
        Computer            = $obj.Computer
        ArcCompatible       = $obj.ArcCompatible
        PowershellVersion   = $obj.PowershellVersion
        FrameworkVersion    = $obj.FrameworkVersion
        AgentStatus         = $agentstatus
        AgentLastHeartbeat  = $obj.AgentLastHeartbeat
        httpsProxy          = $obj.httpsProxy
        AgentErrorCode      = $obj.AgentErrorCode
        AgentErrorTimestamp = $obj.AgentErrorTimestamp
        AgentErrorDetails   = $obj.AgentErrorDetails

    }
}



#Upload data to workspace

Write-Output "Uploading data to Log Analytics Workspace ..."

foreach ($server in $servers) {

    $json = $server | ConvertTo-Json
    $TimeStampField = "LastWriteTime"

    # Submit the data to the API endpoint
    $response = Post-LogAnalyticsData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $logType
    if ($response -ne 200) {
        throw "There was an error sending data to Log Analytics"
    }

}
Write-Output "Data was uploaded to Log Analytics"
