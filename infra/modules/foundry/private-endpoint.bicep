// Creates bare private endpoints only, with no privateDnsZoneGroups child resources.
// DNS zone group association is a separate, later step: see ./private-endpoint-dns.bicep.
param location string
param privateEndpointSubnetId string
param foundryAccountId string
param storageAccountId string
param keyVaultId string
param foundryPrivateEndpointGroupIds array = [
  'account'
]
param storagePrivateEndpointGroupIds array = [
  'blob'
]
param keyVaultPrivateEndpointGroupIds array = [
  'vault'
]

@description('Create a private endpoint for Storage. Set to false when an existing (BYO) storage account already has one.')
param createStoragePrivateEndpoint bool = true

@description('Create a private endpoint for Cosmos DB. Set to false when an existing (BYO) Cosmos DB account already has one.')
param createCosmosDBPrivateEndpoint bool = true

@description('Cosmos DB account resource ID. Required when createCosmosDBPrivateEndpoint is true.')
param cosmosDBAccountId string = ''

@description('Create a private endpoint for AI Search. Set to false when an existing (BYO) AI Search service already has one.')
param createAISearchPrivateEndpoint bool = true

@description('AI Search service resource ID. Required when createAISearchPrivateEndpoint is true.')
param aiSearchServiceId string = ''

@description('Tags to apply to every private endpoint created by this module.')
param tags object = {}

var _validateStoragePrivateEndpointInputs = createStoragePrivateEndpoint && empty(storageAccountId) ? fail('storageAccountId is required when createStoragePrivateEndpoint is true.') : true
var _validateCosmosPrivateEndpointInputs = createCosmosDBPrivateEndpoint && empty(cosmosDBAccountId) ? fail('cosmosDBAccountId is required when createCosmosDBPrivateEndpoint is true.') : true
var _validateAISearchPrivateEndpointInputs = createAISearchPrivateEndpoint && empty(aiSearchServiceId) ? fail('aiSearchServiceId is required when createAISearchPrivateEndpoint is true.') : true

resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-foundry'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'foundry-connection'
        properties: {
          privateLinkServiceId: foundryAccountId
          groupIds: foundryPrivateEndpointGroupIds
        }
      }
    ]
  }
}

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createStoragePrivateEndpoint && _validateStoragePrivateEndpointInputs) {
  name: 'pe-foundry-storage'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-blob-connection'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: storagePrivateEndpointGroupIds
        }
      }
    ]
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-foundry-keyvault'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'keyvault-connection'
        properties: {
          privateLinkServiceId: keyVaultId
          groupIds: keyVaultPrivateEndpointGroupIds
        }
      }
    ]
  }
}

resource cosmosDBPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createCosmosDBPrivateEndpoint && _validateCosmosPrivateEndpointInputs) {
  name: 'pe-foundry-cosmosdb'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'cosmosdb-connection'
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

resource aiSearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createAISearchPrivateEndpoint && _validateAISearchPrivateEndpointInputs) {
  name: 'pe-foundry-aisearch'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'aisearch-connection'
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

output foundryPrivateEndpointId string = foundryPrivateEndpoint.id
output foundryPrivateEndpointName string = foundryPrivateEndpoint.name
// The conditional resources above are guaranteed to exist when these outputs are read because
// createStoragePrivateEndpoint/createCosmosDBPrivateEndpoint/createAISearchPrivateEndpoint gate
// both the resource and any caller's use of the corresponding output.
#disable-next-line BCP318
output storagePrivateEndpointId string = createStoragePrivateEndpoint ? storagePrivateEndpoint.id : ''
#disable-next-line BCP318
output storagePrivateEndpointName string = createStoragePrivateEndpoint ? storagePrivateEndpoint.name : ''
output keyVaultPrivateEndpointId string = keyVaultPrivateEndpoint.id
output keyVaultPrivateEndpointName string = keyVaultPrivateEndpoint.name
#disable-next-line BCP318
output cosmosDBPrivateEndpointId string = createCosmosDBPrivateEndpoint ? cosmosDBPrivateEndpoint.id : ''
#disable-next-line BCP318
output cosmosDBPrivateEndpointName string = createCosmosDBPrivateEndpoint ? cosmosDBPrivateEndpoint.name : ''
#disable-next-line BCP318
output aiSearchPrivateEndpointId string = createAISearchPrivateEndpoint ? aiSearchPrivateEndpoint.id : ''
#disable-next-line BCP318
output aiSearchPrivateEndpointName string = createAISearchPrivateEndpoint ? aiSearchPrivateEndpoint.name : ''
