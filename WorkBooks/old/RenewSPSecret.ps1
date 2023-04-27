#requires -Modules AzureAD
<#
.DESCRIPTION
    This Script can be used to renew the secret of the Service principal used for Azure Arc onboarding
    at scale.
    All the remaining secrets from the Service Principal will be removed!

.PARAMETER ServicePrincipalObjectID
   ObjectID of the Service Principal

.PARAMETER  Months
   Number of Months for which the secret will be valid
 
.EXAMPLE
   This example generates a new secret with a duration of 12 month

   .\RenewSPSecret.ps1 -ServicePrincipalObjectID 26119e8a-4420-4234-9dce-35b3e8dd3ea0 -Months 12
#>

Param (
    [Parameter(Mandatory=$true)]
    [string]$ServicePrincipalObjectID,
    [string]$Months = 12

)

#Main

#region Login Azure AD
try {Get-AzureADCurrentSessionInfo -ErrorAction Stop}
catch {Connect-AzureAD}
#endregion


$startDate = Get-Date
$endDate = $startDate.AddMonths($Months)

$app = Get-AzureADApplication -ObjectId $ServicePrincipalObjectID 

#Remove the current Secret(s)

$Currentsecrets = Get-AzureADApplicationPasswordCredential -ObjectId $app.ObjectId
$Currentsecrets | ForEach-Object { Remove-AzureADApplicationPasswordCredential -ObjectId $app.ObjectId -KeyId $_.Keyid -Verbose }

#Create new secret

$Appsecret = New-AzureADApplicationPasswordCredential -ObjectId $app.ObjectId -CustomKeyIdentifier "ArcSPSecret" -StartDate $startDate -EndDate $endDate
$Spsecret = $Appsecret.Value


Write-Host "Secret from the service principal renewed successfully!" -ForegroundColor Green
$Appsecret

#Generate Random key

$Key = New-Object -TypeName Byte[] 32   # AES, 16, 24, or 32 Bytes
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key) # Fills the $key with bytes

#Encrypt the secret with the random.key
$keytostore = ($key | ForEach-Object { ("{0:x}" -f $_).PadLeft(2, '0') }) -join ""
$spsecretencrypted = ($Spsecret | ConvertTo-SecureString -AsPlainText -Force) | ConvertFrom-SecureString -Key $Key

$Registrationkey = $keytostore
$Registrationinfo = $spsecretencrypted

Write-Host "Please update the Arc Group Policy with the following information in the branch" -ForegroundColor Cyan
Write-Host "Preferences\Windows Settings\Registry `n" -ForegroundColor Green

Write-Host "Registrationkey: " -ForegroundColor Green
Write-Host "$Registrationkey" -ForegroundColor Yellow
Write-Host "`n"
Write-Host "Registrationinfo: " -ForegroundColor Green
Write-Host "$Registrationinfo" -ForegroundColor Yellow