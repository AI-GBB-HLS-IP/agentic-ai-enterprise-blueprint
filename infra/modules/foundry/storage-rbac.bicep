targetScope = 'resourceGroup'

@description('Principal ID of the Foundry project managed identity.')
param projectPrincipalId string

@description('Storage account name (in this module\'s deployment scope).')
param storageAccountName string

@description('Formatted (dashed) project workspace GUID used to scope the ABAC condition below to this project\'s auto-provisioned blob container.')
param projectWorkspaceIdGuid string

// Built-in role: Storage Blob Data Contributor, granted account-wide (unconditional) so the
// Foundry project's managed identity can read/write the platform-managed
// `{workspaceId}-azureml-blobstore` container used for standard agent state/data I/O.
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

// Built-in role: Storage Blob Data Owner, restricted via an ABAC condition to only the
// blob container(s) the Foundry Agent Service platform auto-provisions for this project
// (named `{workspaceId}...-azureml-agent`). Owner (rather than Contributor) is required on this
// container because the agent service manages access on it; this mirrors the customer-provided
// reference template's split between account-wide Contributor and container-scoped Owner.
var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')

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
  }
}

resource storageBlobDataOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(projectPrincipalId, storageBlobDataOwnerRoleId, storageAccount.id)
  scope: storageAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalType: 'ServicePrincipal'
    conditionVersion: '2.0'
    condition: '((ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read\'} OR ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action\'} OR ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write\'}) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase \'${projectWorkspaceIdGuid}\' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase \'*-azureml-agent\'))'
  }
}
