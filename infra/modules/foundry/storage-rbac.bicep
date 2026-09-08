targetScope = 'resourceGroup'

@description('Principal ID of the Foundry project managed identity.')
param projectPrincipalId string

@description('Storage account name (in this module\'s deployment scope).')
param storageAccountName string

@description('Formatted (dashed) project workspace GUID used to scope the ABAC condition below to this project\'s auto-provisioned blob container.')
param projectWorkspaceIdGuid string

// Built-in role: Storage Blob Data Contributor, restricted via an ABAC condition to only the
// blob container(s) the Foundry Agent Service platform auto-provisions for this project
// (named `{workspaceId}...-azureml-agent`). This mirrors the customer-provided reference
// template's least-privilege scoping rather than granting account-wide blob access.
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource storageBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(projectPrincipalId, storageBlobDataContributorRoleId, storageAccount.id)
  scope: storageAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: storageBlobDataContributorRoleId
    principalType: 'ServicePrincipal'
    conditionVersion: '2.0'
    condition: '((!(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read\'})  AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action\'}) AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write\'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase \'${projectWorkspaceIdGuid}\' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase \'*-azureml-agent\'))'
  }
}
