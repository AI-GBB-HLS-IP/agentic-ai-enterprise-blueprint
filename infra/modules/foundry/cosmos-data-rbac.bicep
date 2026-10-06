targetScope = 'resourceGroup'

@description('Principal ID of the Foundry project managed identity.')
param projectPrincipalId string

@description('Cosmos DB account name (in this module\'s deployment scope).')
param cosmosDBAccountName string

@description('Formatted (dashed) project workspace GUID, used only to make the role assignment name deterministic and unique per project.')
param projectWorkspaceIdGuid string

// Built-in Cosmos DB SQL role: Cosmos DB Built-in Data Contributor (data-plane). Per Microsoft's
// reference implementation, this is assigned once at the `enterprise_memory` *database* scope,
// which covers all of the platform-managed containers within it -- individual container-level
// role assignments are not needed (and the containers do not exist yet at this point anyway).
//
// This module must run *after* the Capability Host is created: Capability Host activation is what
// causes the Foundry Agent Service platform to auto-provision the `enterprise_memory` database (and
// its containers), and Cosmos DB SQL role assignments fail with "database ... could not be found"
// if the target database does not already exist at assignment time.
var cosmosDataContributorSqlRoleId = resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', cosmosDBAccountName, '00000000-0000-0000-0000-000000000002')

resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDBAccountName
}

resource enterpriseMemoryDataContributorAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
  parent: cosmosDBAccount
  name: guid(projectWorkspaceIdGuid, cosmosDBAccountName, cosmosDataContributorSqlRoleId, projectPrincipalId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDataContributorSqlRoleId
    scope: '${cosmosDBAccount.id}/dbs/enterprise_memory'
  }
}
