targetScope = 'resourceGroup'

@description('Private endpoint location.')
param location string

@description('Subnet ID in which newly created private endpoints are placed.')
param privateEndpointSubnetId string

@description('Storage account resource ID from the shared-service handoff.')
param storageAccountId string

@description('Key Vault resource ID from the shared-service handoff.')
param keyVaultId string

@description('Cosmos DB account resource ID from the shared-service handoff.')
param cosmosDBAccountId string

@description('Azure AI Search service resource ID from the shared-service handoff.')
param aiSearchServiceId string

@description('Explicitly create a new Storage private endpoint; false means reuse the supplied endpoint ID.')
param createStoragePrivateEndpoint bool

@description('Existing Storage private endpoint ID required when createStoragePrivateEndpoint is false.')
param storagePrivateEndpointId string = ''

@description('Explicitly create a new Key Vault private endpoint; false means reuse the supplied endpoint ID.')
param createKeyVaultPrivateEndpoint bool

@description('Existing Key Vault private endpoint ID required when createKeyVaultPrivateEndpoint is false.')
param keyVaultPrivateEndpointId string = ''

@description('Explicitly create a new Cosmos DB private endpoint; false means reuse the supplied endpoint ID.')
param createCosmosDBPrivateEndpoint bool

@description('Existing Cosmos DB private endpoint ID required when createCosmosDBPrivateEndpoint is false.')
param cosmosDBPrivateEndpointId string = ''

@description('Explicitly create a new Azure AI Search private endpoint; false means reuse the supplied endpoint ID.')
param createAISearchPrivateEndpoint bool

@description('Existing Azure AI Search private endpoint ID required when createAISearchPrivateEndpoint is false.')
param aiSearchPrivateEndpointId string = ''

@description('Approved, owner-managed AMPLS private endpoint ID. This module only references it.')
param approvedAmplsPrivateEndpointId string

@description('Approved Azure Monitor Private Link Scope resource ID targeted by the supplied AMPLS endpoint.')
param approvedAmplsResourceId string

@description('Tags applied only to newly created private endpoints.')
param tags object = {}

var subnetParts = split(privateEndpointSubnetId, '/')
var _validateSubnetId = ((length(subnetParts) == 11) || (length(subnetParts) == 12 && empty(subnetParts[11]))) && toLower(subnetParts[1]) == 'subscriptions' && toLower(subnetParts[3]) == 'resourcegroups' && toLower(subnetParts[5]) == 'providers' && toLower(subnetParts[6]) == 'microsoft.network' && toLower(subnetParts[7]) == 'virtualnetworks' && !empty(subnetParts[8]) && toLower(subnetParts[9]) == 'subnets' && !empty(subnetParts[10])
  ? true
  : fail('privateEndpointSubnetId must be a full ARM resource ID for Microsoft.Network/virtualNetworks/subnets.')

var storageTargetParts = split(storageAccountId, '/')
var _validateStorageTargetId = ((length(storageTargetParts) == 9) || (length(storageTargetParts) == 10 && empty(storageTargetParts[9]))) && toLower(storageTargetParts[1]) == 'subscriptions' && toLower(storageTargetParts[3]) == 'resourcegroups' && toLower(storageTargetParts[5]) == 'providers' && toLower(storageTargetParts[6]) == 'microsoft.storage' && toLower(storageTargetParts[7]) == 'storageaccounts' && !empty(storageTargetParts[8])
  ? true
  : fail('storageAccountId must be a full ARM resource ID for Microsoft.Storage/storageAccounts.')

var keyVaultTargetParts = split(keyVaultId, '/')
var _validateKeyVaultTargetId = ((length(keyVaultTargetParts) == 9) || (length(keyVaultTargetParts) == 10 && empty(keyVaultTargetParts[9]))) && toLower(keyVaultTargetParts[1]) == 'subscriptions' && toLower(keyVaultTargetParts[3]) == 'resourcegroups' && toLower(keyVaultTargetParts[5]) == 'providers' && toLower(keyVaultTargetParts[6]) == 'microsoft.keyvault' && toLower(keyVaultTargetParts[7]) == 'vaults' && !empty(keyVaultTargetParts[8])
  ? true
  : fail('keyVaultId must be a full ARM resource ID for Microsoft.KeyVault/vaults.')

var cosmosTargetParts = split(cosmosDBAccountId, '/')
var _validateCosmosTargetId = ((length(cosmosTargetParts) == 9) || (length(cosmosTargetParts) == 10 && empty(cosmosTargetParts[9]))) && toLower(cosmosTargetParts[1]) == 'subscriptions' && toLower(cosmosTargetParts[3]) == 'resourcegroups' && toLower(cosmosTargetParts[5]) == 'providers' && toLower(cosmosTargetParts[6]) == 'microsoft.documentdb' && toLower(cosmosTargetParts[7]) == 'databaseaccounts' && !empty(cosmosTargetParts[8])
  ? true
  : fail('cosmosDBAccountId must be a full ARM resource ID for Microsoft.DocumentDB/databaseAccounts.')

var searchTargetParts = split(aiSearchServiceId, '/')
var _validateSearchTargetId = ((length(searchTargetParts) == 9) || (length(searchTargetParts) == 10 && empty(searchTargetParts[9]))) && toLower(searchTargetParts[1]) == 'subscriptions' && toLower(searchTargetParts[3]) == 'resourcegroups' && toLower(searchTargetParts[5]) == 'providers' && toLower(searchTargetParts[6]) == 'microsoft.search' && toLower(searchTargetParts[7]) == 'searchservices' && !empty(searchTargetParts[8])
  ? true
  : fail('aiSearchServiceId must be a full ARM resource ID for Microsoft.Search/searchServices.')

var storageEndpointParts = split(storagePrivateEndpointId, '/')
var _validateStorageEndpointChoice = (createStoragePrivateEndpoint && empty(storagePrivateEndpointId)) || (!createStoragePrivateEndpoint && ((length(storageEndpointParts) == 9 || (length(storageEndpointParts) == 10 && empty(storageEndpointParts[9]))) && toLower(storageEndpointParts[1]) == 'subscriptions' && toLower(storageEndpointParts[3]) == 'resourcegroups' && toLower(storageEndpointParts[5]) == 'providers' && toLower(storageEndpointParts[6]) == 'microsoft.network' && toLower(storageEndpointParts[7]) == 'privateendpoints' && !empty(storageEndpointParts[8]))) ? true : fail('Choose Storage endpoint creation or provide a full existing Microsoft.Network/privateEndpoints resource ID.')
var storageEndpointSubscriptionId = createStoragePrivateEndpoint ? subscription().subscriptionId : (_validateStorageEndpointChoice ? storageEndpointParts[2] : '')
var storageEndpointResourceGroupName = createStoragePrivateEndpoint ? resourceGroup().name : (_validateStorageEndpointChoice ? storageEndpointParts[4] : '')
var storageEndpointName = createStoragePrivateEndpoint
  ? (_validateStorageTargetId && _validateSubnetId ? 'pe-agent-storage' : fail('valid storageAccountId and privateEndpointSubnetId are required for Storage endpoint creation.'))
  : (_validateStorageEndpointChoice && _validateStorageTargetId ? storageEndpointParts[8] : fail('valid storageAccountId and a full existing private endpoint ID are required for Storage endpoint reuse.'))

resource existingStoragePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = if (!createStoragePrivateEndpoint) {
  scope: resourceGroup(storageEndpointSubscriptionId, storageEndpointResourceGroupName)
  name: storageEndpointName
}

resource newStoragePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createStoragePrivateEndpoint && _validateStorageEndpointChoice) {
  name: storageEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'phase1-agent-storage-connection'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

var keyVaultEndpointParts = split(keyVaultPrivateEndpointId, '/')
var _validateKeyVaultEndpointChoice = (createKeyVaultPrivateEndpoint && empty(keyVaultPrivateEndpointId)) || (!createKeyVaultPrivateEndpoint && ((length(keyVaultEndpointParts) == 9 || (length(keyVaultEndpointParts) == 10 && empty(keyVaultEndpointParts[9]))) && toLower(keyVaultEndpointParts[1]) == 'subscriptions' && toLower(keyVaultEndpointParts[3]) == 'resourcegroups' && toLower(keyVaultEndpointParts[5]) == 'providers' && toLower(keyVaultEndpointParts[6]) == 'microsoft.network' && toLower(keyVaultEndpointParts[7]) == 'privateendpoints' && !empty(keyVaultEndpointParts[8]))) ? true : fail('Choose Key Vault endpoint creation or provide a full existing Microsoft.Network/privateEndpoints resource ID.')
var keyVaultEndpointSubscriptionId = createKeyVaultPrivateEndpoint ? subscription().subscriptionId : (_validateKeyVaultEndpointChoice ? keyVaultEndpointParts[2] : '')
var keyVaultEndpointResourceGroupName = createKeyVaultPrivateEndpoint ? resourceGroup().name : (_validateKeyVaultEndpointChoice ? keyVaultEndpointParts[4] : '')
var keyVaultEndpointName = createKeyVaultPrivateEndpoint
  ? (_validateKeyVaultTargetId && _validateSubnetId ? 'pe-agent-keyvault' : fail('valid keyVaultId and privateEndpointSubnetId are required for Key Vault endpoint creation.'))
  : (_validateKeyVaultEndpointChoice && _validateKeyVaultTargetId ? keyVaultEndpointParts[8] : fail('valid keyVaultId and a full existing private endpoint ID are required for Key Vault endpoint reuse.'))

resource existingKeyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = if (!createKeyVaultPrivateEndpoint) {
  scope: resourceGroup(keyVaultEndpointSubscriptionId, keyVaultEndpointResourceGroupName)
  name: keyVaultEndpointName
}

resource newKeyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createKeyVaultPrivateEndpoint && _validateKeyVaultEndpointChoice) {
  name: keyVaultEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'phase1-agent-keyvault-connection'
        properties: {
          privateLinkServiceId: keyVaultId
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

var cosmosEndpointParts = split(cosmosDBPrivateEndpointId, '/')
var _validateCosmosEndpointChoice = (createCosmosDBPrivateEndpoint && empty(cosmosDBPrivateEndpointId)) || (!createCosmosDBPrivateEndpoint && ((length(cosmosEndpointParts) == 9 || (length(cosmosEndpointParts) == 10 && empty(cosmosEndpointParts[9]))) && toLower(cosmosEndpointParts[1]) == 'subscriptions' && toLower(cosmosEndpointParts[3]) == 'resourcegroups' && toLower(cosmosEndpointParts[5]) == 'providers' && toLower(cosmosEndpointParts[6]) == 'microsoft.network' && toLower(cosmosEndpointParts[7]) == 'privateendpoints' && !empty(cosmosEndpointParts[8]))) ? true : fail('Choose Cosmos DB endpoint creation or provide a full existing Microsoft.Network/privateEndpoints resource ID.')
var cosmosEndpointSubscriptionId = createCosmosDBPrivateEndpoint ? subscription().subscriptionId : (_validateCosmosEndpointChoice ? cosmosEndpointParts[2] : '')
var cosmosEndpointResourceGroupName = createCosmosDBPrivateEndpoint ? resourceGroup().name : (_validateCosmosEndpointChoice ? cosmosEndpointParts[4] : '')
var cosmosEndpointName = createCosmosDBPrivateEndpoint
  ? (_validateCosmosTargetId && _validateSubnetId ? 'pe-agent-cosmosdb' : fail('valid cosmosDBAccountId and privateEndpointSubnetId are required for Cosmos DB endpoint creation.'))
  : (_validateCosmosEndpointChoice && _validateCosmosTargetId ? cosmosEndpointParts[8] : fail('valid cosmosDBAccountId and a full existing private endpoint ID are required for Cosmos DB endpoint reuse.'))

resource existingCosmosDBPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = if (!createCosmosDBPrivateEndpoint) {
  scope: resourceGroup(cosmosEndpointSubscriptionId, cosmosEndpointResourceGroupName)
  name: cosmosEndpointName
}

resource newCosmosDBPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createCosmosDBPrivateEndpoint && _validateCosmosEndpointChoice) {
  name: cosmosEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'phase1-agent-cosmos-connection'
        properties: {
          privateLinkServiceId: cosmosDBAccountId
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

var searchEndpointParts = split(aiSearchPrivateEndpointId, '/')
var _validateSearchEndpointChoice = (createAISearchPrivateEndpoint && empty(aiSearchPrivateEndpointId)) || (!createAISearchPrivateEndpoint && ((length(searchEndpointParts) == 9 || (length(searchEndpointParts) == 10 && empty(searchEndpointParts[9]))) && toLower(searchEndpointParts[1]) == 'subscriptions' && toLower(searchEndpointParts[3]) == 'resourcegroups' && toLower(searchEndpointParts[5]) == 'providers' && toLower(searchEndpointParts[6]) == 'microsoft.network' && toLower(searchEndpointParts[7]) == 'privateendpoints' && !empty(searchEndpointParts[8]))) ? true : fail('Choose Azure AI Search endpoint creation or provide a full existing Microsoft.Network/privateEndpoints resource ID.')
var searchEndpointSubscriptionId = createAISearchPrivateEndpoint ? subscription().subscriptionId : (_validateSearchEndpointChoice ? searchEndpointParts[2] : '')
var searchEndpointResourceGroupName = createAISearchPrivateEndpoint ? resourceGroup().name : (_validateSearchEndpointChoice ? searchEndpointParts[4] : '')
var searchEndpointName = createAISearchPrivateEndpoint
  ? (_validateSearchTargetId && _validateSubnetId ? 'pe-agent-aisearch' : fail('valid aiSearchServiceId and privateEndpointSubnetId are required for Azure AI Search endpoint creation.'))
  : (_validateSearchEndpointChoice && _validateSearchTargetId ? searchEndpointParts[8] : fail('valid aiSearchServiceId and a full existing private endpoint ID are required for Azure AI Search endpoint reuse.'))

resource existingAISearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = if (!createAISearchPrivateEndpoint) {
  scope: resourceGroup(searchEndpointSubscriptionId, searchEndpointResourceGroupName)
  name: searchEndpointName
}

resource newAISearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createAISearchPrivateEndpoint && _validateSearchEndpointChoice) {
  name: searchEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'phase1-agent-search-connection'
        properties: {
          privateLinkServiceId: aiSearchServiceId
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
}

var amplsEndpointParts = split(approvedAmplsPrivateEndpointId, '/')
var _validateAmplsEndpointId = ((length(amplsEndpointParts) == 9) || (length(amplsEndpointParts) == 10 && empty(amplsEndpointParts[9]))) && toLower(amplsEndpointParts[1]) == 'subscriptions' && toLower(amplsEndpointParts[3]) == 'resourcegroups' && toLower(amplsEndpointParts[5]) == 'providers' && toLower(amplsEndpointParts[6]) == 'microsoft.network' && toLower(amplsEndpointParts[7]) == 'privateendpoints' && !empty(amplsEndpointParts[8])
  ? true
  : fail('approvedAmplsPrivateEndpointId must be a full owner-managed Microsoft.Network/privateEndpoints resource ID.')
var amplsEndpointName = _validateAmplsEndpointId ? amplsEndpointParts[8] : ''
var amplsEndpointSubscriptionId = _validateAmplsEndpointId ? amplsEndpointParts[2] : ''
var amplsEndpointResourceGroupName = _validateAmplsEndpointId ? amplsEndpointParts[4] : ''
var amplsTargetParts = split(approvedAmplsResourceId, '/')
var _validateAmplsTargetId = ((length(amplsTargetParts) == 9) || (length(amplsTargetParts) == 10 && empty(amplsTargetParts[9]))) && toLower(amplsTargetParts[1]) == 'subscriptions' && toLower(amplsTargetParts[3]) == 'resourcegroups' && toLower(amplsTargetParts[5]) == 'providers' && toLower(amplsTargetParts[6]) == 'microsoft.insights' && toLower(amplsTargetParts[7]) == 'privatelinkscopes' && !empty(amplsTargetParts[8])
  ? true
  : fail('approvedAmplsResourceId must be a full ARM resource ID for Microsoft.Insights/privateLinkScopes.')
var validatedAmplsEndpointName = _validateAmplsEndpointId && _validateAmplsTargetId ? amplsEndpointName : fail('A valid AMPLS endpoint and target resource ID are required.')

resource approvedAmplsPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = {
  scope: resourceGroup(amplsEndpointSubscriptionId, amplsEndpointResourceGroupName)
  name: validatedAmplsEndpointName
}

#disable-next-line BCP318
output storagePrivateEndpointId string = createStoragePrivateEndpoint ? newStoragePrivateEndpoint.id : existingStoragePrivateEndpoint.id
#disable-next-line BCP318
output keyVaultPrivateEndpointId string = createKeyVaultPrivateEndpoint ? newKeyVaultPrivateEndpoint.id : existingKeyVaultPrivateEndpoint.id
#disable-next-line BCP318
output cosmosDBPrivateEndpointId string = createCosmosDBPrivateEndpoint ? newCosmosDBPrivateEndpoint.id : existingCosmosDBPrivateEndpoint.id
#disable-next-line BCP318
output aiSearchPrivateEndpointId string = createAISearchPrivateEndpoint ? newAISearchPrivateEndpoint.id : existingAISearchPrivateEndpoint.id
output amplsPrivateEndpointId string = approvedAmplsPrivateEndpoint.id
