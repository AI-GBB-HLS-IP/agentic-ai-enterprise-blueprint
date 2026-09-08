@description('Foundry account name.')
param foundryAccountName string

@description('Foundry project name.')
param projectName string

@description('Cosmos DB account name used as the connection name.')
param cosmosDBAccountName string

@description('Cosmos DB document endpoint (BYO or newly created).')
param cosmosDBDocumentEndpoint string

@description('Cosmos DB account resource ID (BYO or newly created), used for connection metadata.')
param cosmosDBAccountId string

@description('Cosmos DB account location, used for connection metadata.')
param cosmosDBLocation string

@description('Storage account name used as the connection name.')
param storageAccountName string

@description('Storage account blob endpoint (BYO or newly created).')
param storageBlobEndpoint string

@description('Storage account resource ID (BYO or newly created), used for connection metadata.')
param storageAccountId string

@description('Storage account location, used for connection metadata.')
param storageLocation string

@description('AI Search service name used as the connection name.')
param aiSearchServiceName string

@description('AI Search service resource ID (BYO or newly created), used for connection metadata.')
param aiSearchServiceId string

@description('AI Search service location, used for connection metadata.')
param aiSearchLocation string

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: account
  name: projectName
}

resource cosmosDBConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: cosmosDBAccountName
  properties: {
    category: 'CosmosDB'
    target: cosmosDBDocumentEndpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosDBAccountId
      location: cosmosDBLocation
    }
  }
}

resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: storageAccountName
  properties: {
    category: 'AzureStorageAccount'
    target: storageBlobEndpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccountId
      location: storageLocation
    }
  }
}

resource aiSearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: aiSearchServiceName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${aiSearchServiceName}.search.windows.net'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiSearchServiceId
      location: aiSearchLocation
    }
  }
}

output cosmosDBConnectionName string = cosmosDBConnection.name
output storageConnectionName string = storageConnection.name
output aiSearchConnectionName string = aiSearchConnection.name
