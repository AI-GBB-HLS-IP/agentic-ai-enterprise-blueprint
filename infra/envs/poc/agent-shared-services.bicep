targetScope = 'resourceGroup'

@description('Deployment location for newly created shared services.')
param location string = resourceGroup().location

@description('Storage account name used only when creating a new account.')
param storageAccountName string

@description('Existing Storage account full ARM resource ID. Leave empty to create a new account.')
param existingAzureStorageAccountResourceId string = ''

@description('Key Vault name used only when creating a new vault.')
param keyVaultName string

@description('Existing Key Vault full ARM resource ID. Leave empty to create a new vault.')
param existingKeyVaultResourceId string = ''

@description('AI Search service name used only when creating a new service.')
param aiSearchServiceName string

@description('Existing AI Search service full ARM resource ID. Leave empty to create a new service.')
param existingAISearchResourceId string = ''

@description('Cosmos DB account name used only when creating a new account.')
param cosmosDBAccountName string

@description('Existing Cosmos DB account full ARM resource ID. Leave empty to create a new account.')
param existingAzureCosmosDBAccountResourceId string = ''

@description('Tags to apply to newly created shared services.')
param tags object = {
  'phase1-agent-platform': 'true'
}

var storagePassedIn = !empty(existingAzureStorageAccountResourceId)
var storageParts = split(existingAzureStorageAccountResourceId, '/')
var _validateStorageResourceId = !storagePassedIn || (((length(storageParts) == 9) || (length(storageParts) == 10 && empty(storageParts[9]))) && toLower(storageParts[1]) == 'subscriptions' && toLower(storageParts[3]) == 'resourcegroups' && toLower(storageParts[5]) == 'providers' && toLower(storageParts[6]) == 'microsoft.storage' && toLower(storageParts[7]) == 'storageaccounts' && !empty(storageParts[8])) ? true : fail('existingAzureStorageAccountResourceId must be a full ARM resource ID for Microsoft.Storage/storageAccounts.')
var storageSubscriptionId = storagePassedIn ? storageParts[2] : subscription().subscriptionId
var storageResourceGroupName = storagePassedIn ? storageParts[4] : resourceGroup().name
var storageAccountNameResolved = _validateStorageResourceId
  ? (storagePassedIn ? storageParts[8] : storageAccountName)
  : ''

resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (storagePassedIn) {
  scope: resourceGroup(storageSubscriptionId, storageResourceGroupName)
  name: storageAccountNameResolved
}

module newStorageAccount '../../modules/foundry/storage.bicep' = if (!storagePassedIn) {
  name: 'phase1-agent-storage'
  scope: resourceGroup(storageSubscriptionId, storageResourceGroupName)
  params: {
    location: location
    storageAccountName: storageAccountNameResolved
    tags: tags
  }
}

var searchPassedIn = !empty(existingAISearchResourceId)
var searchParts = split(existingAISearchResourceId, '/')
var _validateSearchResourceId = !searchPassedIn || (((length(searchParts) == 9) || (length(searchParts) == 10 && empty(searchParts[9]))) && toLower(searchParts[1]) == 'subscriptions' && toLower(searchParts[3]) == 'resourcegroups' && toLower(searchParts[5]) == 'providers' && toLower(searchParts[6]) == 'microsoft.search' && toLower(searchParts[7]) == 'searchservices' && !empty(searchParts[8])) ? true : fail('existingAISearchResourceId must be a full ARM resource ID for Microsoft.Search/searchServices.')
var searchSubscriptionId = searchPassedIn ? searchParts[2] : subscription().subscriptionId
var searchResourceGroupName = searchPassedIn ? searchParts[4] : resourceGroup().name
var aiSearchServiceNameResolved = _validateSearchResourceId
  ? (searchPassedIn ? searchParts[8] : aiSearchServiceName)
  : ''

resource existingAISearchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = if (searchPassedIn) {
  scope: resourceGroup(searchSubscriptionId, searchResourceGroupName)
  name: aiSearchServiceNameResolved
}

module newAISearchService '../../modules/foundry/ai-search.bicep' = if (!searchPassedIn) {
  name: 'phase1-agent-ai-search'
  scope: resourceGroup(searchSubscriptionId, searchResourceGroupName)
  params: {
    location: location
    aiSearchServiceName: aiSearchServiceNameResolved
    tags: tags
  }
}

var cosmosPassedIn = !empty(existingAzureCosmosDBAccountResourceId)
var cosmosParts = split(existingAzureCosmosDBAccountResourceId, '/')
var _validateCosmosResourceId = !cosmosPassedIn || (((length(cosmosParts) == 9) || (length(cosmosParts) == 10 && empty(cosmosParts[9]))) && toLower(cosmosParts[1]) == 'subscriptions' && toLower(cosmosParts[3]) == 'resourcegroups' && toLower(cosmosParts[5]) == 'providers' && toLower(cosmosParts[6]) == 'microsoft.documentdb' && toLower(cosmosParts[7]) == 'databaseaccounts' && !empty(cosmosParts[8])) ? true : fail('existingAzureCosmosDBAccountResourceId must be a full ARM resource ID for Microsoft.DocumentDB/databaseAccounts.')
var cosmosSubscriptionId = cosmosPassedIn ? cosmosParts[2] : subscription().subscriptionId
var cosmosResourceGroupName = cosmosPassedIn ? cosmosParts[4] : resourceGroup().name
var cosmosDBAccountNameResolved = _validateCosmosResourceId
  ? (cosmosPassedIn ? cosmosParts[8] : cosmosDBAccountName)
  : ''

resource existingCosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = if (cosmosPassedIn) {
  scope: resourceGroup(cosmosSubscriptionId, cosmosResourceGroupName)
  name: cosmosDBAccountNameResolved
}

module newCosmosDBAccount '../../modules/foundry/cosmos-db.bicep' = if (!cosmosPassedIn) {
  name: 'phase1-agent-cosmos-db'
  scope: resourceGroup(cosmosSubscriptionId, cosmosResourceGroupName)
  params: {
    location: location
    cosmosDBAccountName: cosmosDBAccountNameResolved
    tags: tags
  }
}

module keyVaultResources '../../modules/foundry/supporting-resources.bicep' = {
  name: 'phase1-agent-key-vault'
  params: {
    location: location
    keyVaultName: keyVaultName
    existingKeyVaultResourceId: existingKeyVaultResourceId
    tags: tags
  }
}

#disable-next-line BCP318
var storageAccountIdResolved = storagePassedIn ? existingStorageAccount.id : newStorageAccount.outputs.storageAccountId
#disable-next-line BCP318
var storageBlobEndpointResolved = storagePassedIn ? existingStorageAccount.properties.primaryEndpoints.blob : 'https://${storageAccountNameResolved}.blob.${environment().suffixes.storage}/'
#disable-next-line BCP318
var aiSearchServiceIdResolved = searchPassedIn ? existingAISearchService.id : newAISearchService.outputs.aiSearchServiceId
#disable-next-line BCP318
var cosmosDBAccountIdResolved = cosmosPassedIn ? existingCosmosDBAccount.id : newCosmosDBAccount.outputs.cosmosDBAccountId
#disable-next-line BCP318
var cosmosDBDocumentEndpointResolved = cosmosPassedIn ? existingCosmosDBAccount.properties.documentEndpoint : newCosmosDBAccount.outputs.cosmosDBDocumentEndpoint
var aiSearchEndpointResolved = 'https://${aiSearchServiceNameResolved}.search.windows.net'

output storageAccountId string = storageAccountIdResolved
output storageBlobEndpoint string = storageBlobEndpointResolved
output storageOwnership string = storagePassedIn ? 'reused' : 'created'
output keyVaultId string = keyVaultResources.outputs.keyVaultId
output keyVaultOwnership string = empty(existingKeyVaultResourceId) ? 'created' : 'reused'
output aiSearchServiceId string = aiSearchServiceIdResolved
output aiSearchEndpoint string = aiSearchEndpointResolved
output aiSearchOwnership string = searchPassedIn ? 'reused' : 'created'
output cosmosDBAccountId string = cosmosDBAccountIdResolved
output cosmosDBDocumentEndpoint string = cosmosDBDocumentEndpointResolved
output cosmosDBOwnership string = cosmosPassedIn ? 'reused' : 'created'
