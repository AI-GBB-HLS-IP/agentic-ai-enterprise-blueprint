@description('Foundry account name.')
param foundryAccountName string

@description('Foundry project name.')
param projectName string

@description('Fixed capability host name for the Agents capability host.')
param projectCapHostName string = 'caphostproj'

@description('Cosmos DB connection name (thread storage).')
param cosmosDBConnectionName string

@description('Storage account connection name (blob storage).')
param storageConnectionName string

@description('AI Search connection name (vector store).')
param aiSearchConnectionName string

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: account
  name: projectName
}

// Activates the Foundry Agent Service runtime for this project, wiring it to the BYO/new
// Cosmos DB (thread storage), Storage (blob storage), and AI Search (vector store) connections.
resource capabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: projectCapHostName
  properties: {
    capabilityHostKind: 'Agents'
    vectorStoreConnections: [
      aiSearchConnectionName
    ]
    storageConnections: [
      storageConnectionName
    ]
    threadStorageConnections: [
      cosmosDBConnectionName
    ]
  }
}

// The Foundry Agent Service platform formats the project's internalId (a raw hex GUID) into
// standard dashed-GUID form to derive the names of the Cosmos containers and Storage container
// it auto-provisions for this project (enterprise_memory database, {workspaceId}-* containers,
// and the {workspaceId}-azureml-agent blob container). RBAC below is pre-authorized against
// those not-yet-existing child scopes, which Azure RBAC permits as long as the parent resource
// (the Cosmos/Storage account) already exists.
var rawWorkspaceId = string(project.properties.internalId)
var _validateWorkspaceId = (length(rawWorkspaceId) == 32) ? true : fail('project.properties.internalId must be a 32-character hex GUID; ensure the selected API version returns internalId.')
var workspaceIdGuid = _validateWorkspaceId
  ? '${substring(rawWorkspaceId, 0, 8)}-${substring(rawWorkspaceId, 8, 4)}-${substring(rawWorkspaceId, 12, 4)}-${substring(rawWorkspaceId, 16, 4)}-${substring(rawWorkspaceId, 20, 12)}'
  : ''

output projectPrincipalId string = project.identity.principalId
output projectWorkspaceIdGuid string = workspaceIdGuid
output capabilityHostId string = capabilityHost.id
