targetScope = 'resourceGroup'

@description('Principal ID of the Foundry project managed identity.')
param projectPrincipalId string

@description('AI Search service name (in this module\'s deployment scope).')
param aiSearchServiceName string

// Built-in roles: Search Index Data Contributor (read/write index data) and Search Service
// Contributor (manage indexes/service configuration).
var searchIndexDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
var searchServiceContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')

resource aiSearchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: aiSearchServiceName
}

resource searchIndexDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(projectPrincipalId, searchIndexDataContributorRoleId, aiSearchService.id)
  scope: aiSearchService
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: searchIndexDataContributorRoleId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(projectPrincipalId, searchServiceContributorRoleId, aiSearchService.id)
  scope: aiSearchService
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: searchServiceContributorRoleId
    principalType: 'ServicePrincipal'
  }
}
