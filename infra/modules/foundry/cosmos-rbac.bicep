targetScope = 'resourceGroup'

@description('Principal ID of the Foundry project managed identity.')
param projectPrincipalId string

@description('Cosmos DB account name (in this module\'s deployment scope).')
param cosmosDBAccountName string

@description('Formatted (dashed) project workspace GUID used to derive the platform-managed container names.')
param projectWorkspaceIdGuid string

// Built-in role: Cosmos DB Operator (management-plane; lets the project read connection strings
// and metadata, but not data).
var cosmosDBOperatorRoleId = resourceId('Microsoft.Authorization/roleDefinitions', '230815da-be43-4aae-9cb4-875f7bd000aa')

// Built-in Cosmos DB SQL role: Cosmos DB Built-in Data Contributor (data-plane; scoped per
// container below, not at the account level).
var cosmosDataContributorSqlRoleId = resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', cosmosDBAccountName, '00000000-0000-0000-0000-000000000002')

var systemThreadContainerName = '${projectWorkspaceIdGuid}-system-thread-message-store'
var userThreadContainerName = '${projectWorkspaceIdGuid}-thread-message-store'
var entityStoreContainerName = '${projectWorkspaceIdGuid}-agent-entity-store'

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

// The three containers below are auto-provisioned by the Foundry Agent Service platform (in
// database `enterprise_memory`) when the capability host is activated; they do not need to be
// created by this blueprint. Azure RBAC allows scoping a role assignment to a child resource
// path that does not exist yet, as long as the parent account already exists.
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
