##  Azure Function ARM Template

This Azure Function is used for the following:

-  It checks for the latest Azure Arc Agent version in https://docs.microsoft.com/en-us/azure/azure-arc/servers/agent-release-notes and shows the latest agent release notes in a workbook
-  It gets information from the Service Principal used to onboard machines in Arc, such as *name*,*creation date* and *expiration date*. This information is shown in the workbook



**Installation:**

-   Deploy *AzureFunctionAgentVersion.json* ARM Template to the desired Resource Group

![ArcFunctionDeployment](../Screenshoot/ArcFunctionDeployment.png)


- Assign the system managed identity of the function the *Directory readers* Azure Active Directory roles, or any equivalent role than can read Applications from AAD


![ServicePrincipalPermissionsDirectoryReaders](\../Screenshoot/ServicePrincipalPermissionsDirectoryReaders.png)



- Restart your Azure Function. The load of PowerShell AZ modules might take some minutes

![AzureFunctionRestart](\../Screenshoot/AzureFunctionRestart.png)


- Run the Function and check that the Log Analytics Custom Logs hav been populated.
  
![AzureFunctionRun](../Screenshoot/AzureFunctionRun.png)

![LogAnalyticsData](\../Screenshoot/LogAnalyticsData.png)
