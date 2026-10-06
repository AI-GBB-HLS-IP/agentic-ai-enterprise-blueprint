targetScope = 'resourceGroup'

@description('Principal ID of the Foundry project managed identity.')
param projectPrincipalId string

@description('Cosmos DB account name (in this module\'s deployment scope).')
param cosmosDBAccountName string

@description('Formatted (dashed) project workspace GUID, used to scope the role assignments to this project and make their names deterministic.')
param projectWorkspaceIdGuid string

// Built-in Cosmos DB SQL role: Cosmos DB Built-in Data Contributor (data-plane). Keep access
// limited to this project's three platform-managed containers in the `enterprise_memory` database.
//
// This module must run *after* the Capability Host is created: Capability Host activation is what
// causes the Foundry Agent Service platform to auto-provision the `enterprise_memory` database (and
// its containers), and Cosmos DB SQL role assignments fail if the target scope does not exist.
var cosmosDataContributorSqlRoleId = resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', cosmosDBAccountName, '00000000-0000-0000-0000-000000000002')
var systemThreadContainerName = '${projectWorkspaceIdGuid}-system-thread-message-store'
var userThreadContainerName = '${projectWorkspaceIdGuid}-thread-message-store'
var entityStoreContainerName = '${projectWorkspaceIdGuid}-agent-entity-store'

resource cosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDBAccountName
}

resource userThreadContainerAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
  parent: cosmosDBAccount
  name: guid(projectWorkspaceIdGuid, userThreadContainerName, cosmosDataContributorSqlRoleId, projectPrincipalId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDataContributorSqlRoleId
    scope: '${cosmosDBAccount.id}/dbs/enterprise_memory/colls/${userThreadContainerName}'
  }
}

resource systemThreadContainerAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
  parent: cosmosDBAccount
  name: guid(projectWorkspaceIdGuid, systemThreadContainerName, cosmosDataContributorSqlRoleId, projectPrincipalId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDataContributorSqlRoleId
    scope: '${cosmosDBAccount.id}/dbs/enterprise_memory/colls/${systemThreadContainerName}'
  }
}

resource entityStoreContainerAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
  parent: cosmosDBAccount
  name: guid(projectWorkspaceIdGuid, entityStoreContainerName, cosmosDataContributorSqlRoleId, projectPrincipalId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDataContributorSqlRoleId
    scope: '${cosmosDBAccount.id}/dbs/enterprise_memory/colls/${entityStoreContainerName}'
  }
}
