##  Azure Function ARM Template

This Azure Function is used for the following:

-  It checks for the latest Azure Arc Agent version in https://docs.microsoft.com/en-us/azure/azure-arc/servers/agent-release-notes and shows the latest agent release notes in a workbook
-  It gets information from the Service Principal used to onboard machines in Arc, such as *name*,*creation date* and *expiration date*. This information is shown in the workbook


**Prerequisites:**

An Azure Keyvault that contains 2 Secrets with the following information:

-   *Workspaceid*: Id of the Log Analytics Workspace to store the information about Azure Arc Versions and Service Principal.
-   *WorkSpacekey*: Key to post data to the Workspace


   ![KeyVaultSecrets](\../Screenshoot/KeyVaultSecrets.png)



**Installation:**

-   Deploy *AzureFunctionAgentVersion.json* ARM Template to the desired Resource Group

![ArcFunctionDeployment](../Screenshoot/ArcFunctionDeployment.png)

   
-   Modify the Key Vault Access policies to allow the Azure Function to access the secrets in the key vault. Use the system managed identity of the function to assign permissions

   ![KeyVaultAccesspolicies](\../Screenshoot/KeyVaultAccesspolicies.png)

- Assign the system managed identity of the function the *Directory readers* Azure Active Directory roles, or any equivalent role than can read Applications from AAD


   ![ServicePrincipalPermissionsDirectoryReaders](\../Screenshoot/ServicePrincipalPermissionsDirectoryReaders.png)



-   Inside the Function App, modify the *requirements.psd1*, delete the line with Az Powershell version and use the following lines instead:
   
         'Az.KeyVault' = '4.*'
         'Az.Resources' = '5.*'

 This will enable the function to use these PowerShell modules.

   ![AzureFuntionRequirements](\../Screenshoot/AzureFuntionRequirements.png)

- Restart your Azure Function. The load of PowerShell az module might take some minutes

![AzureFunctionRestart](\../Screenshoot/AzureFunctionRestart.png)


- Run the Function and check that the Log Analytics log has been populated.
  
![AzureFunctionRun](../Screenshoot/AzureFunctionRun.png)

![LogAnalyticsData](\../Screenshoot/LogAnalyticsData.png)
