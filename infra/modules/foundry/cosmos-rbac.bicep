targetScope = 'resourceGroup'

@description('Principal ID of the Foundry project managed identity.')
param projectPrincipalId string

@description('Cosmos DB account name (in this module\'s deployment scope).')
param cosmosDBAccountName string

// Built-in role: Cosmos DB Operator (management-plane account operations and metadata; does not
// grant Cosmos DB data-plane access). This must be assigned before the Capability Host is created.
var cosmosDBOperatorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '230815da-be43-4aae-9cb4-875f7bd000aa')

resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDBAccountName
}

resource cosmosDBOperatorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(projectPrincipalId, cosmosDBOperatorRoleId, cosmosDBAccount.id)
  scope: cosmosDBAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDBOperatorRoleId
    principalType: 'ServicePrincipal'
  }
}

// NOTE: the project-scoped data-plane Cosmos DB SQL role assignments are handled by
// cosmos-data-rbac.bicep after the Capability Host creates the workspace-prefixed containers.
// See infra/modules/foundry/main.bicep for the dependency ordering.
