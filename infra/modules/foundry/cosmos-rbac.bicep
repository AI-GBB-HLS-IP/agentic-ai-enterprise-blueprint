targetScope = 'resourceGroup'

@description('Principal ID of the Foundry project managed identity.')
param projectPrincipalId string

@description('Cosmos DB account name (in this module\'s deployment scope).')
param cosmosDBAccountName string

// Built-in role: Cosmos DB Operator (management-plane; lets the project read connection strings
// and metadata, but not data). This must be assigned before the Capability Host is created.
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

// NOTE: the data-plane Cosmos DB SQL role assignment (Cosmos DB Built-in Data Contributor,
// scoped to the `enterprise_memory` database) is handled by cosmos-data-rbac.bicep, which must
// run *after* the Capability Host is created -- the platform auto-provisions the
// `enterprise_memory` database (and its containers) during Capability Host activation, and
// Cosmos DB SQL role assignments require the target database to already exist. See
// infra/modules/foundry/main.bicep for the dependency ordering.
