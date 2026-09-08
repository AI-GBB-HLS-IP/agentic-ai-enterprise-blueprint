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
param cognitiveServicesDnsZoneId string
param openAiDnsZoneId string
param servicesAiDnsZoneId string
param blobDnsZoneId string
param keyVaultDnsZoneId string

@description('Create a private endpoint for Storage. Set to false when an existing (BYO) storage account already has one.')
param createStoragePrivateEndpoint bool = true

@description('Create a private endpoint for Cosmos DB. Set to false when an existing (BYO) Cosmos DB account already has one.')
param createCosmosDBPrivateEndpoint bool = true

@description('Cosmos DB account resource ID. Required when createCosmosDBPrivateEndpoint is true.')
param cosmosDBAccountId string = ''

@description('Cosmos DB private DNS zone resource ID. Required when createCosmosDBPrivateEndpoint is true.')
param cosmosDBDnsZoneId string = ''

@description('Create a private endpoint for AI Search. Set to false when an existing (BYO) AI Search service already has one.')
param createAISearchPrivateEndpoint bool = true

@description('AI Search service resource ID. Required when createAISearchPrivateEndpoint is true.')
param aiSearchServiceId string = ''

@description('AI Search private DNS zone resource ID. Required when createAISearchPrivateEndpoint is true.')
param aiSearchDnsZoneId string = ''


resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-foundry'
  location: location
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

resource foundryDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  name: 'foundry-dns'
  parent: foundryPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cognitive-services'
        properties: {
          privateDnsZoneId: cognitiveServicesDnsZoneId
        }
      }
      {
        name: 'openai'
        properties: {
          privateDnsZoneId: openAiDnsZoneId
        }
      }
      {
        name: 'services-ai'
        properties: {
          privateDnsZoneId: servicesAiDnsZoneId
        }
      }
    ]
  }
}

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createStoragePrivateEndpoint) {
  name: 'pe-foundry-storage'
  location: location
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

resource storageDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (createStoragePrivateEndpoint) {
  name: 'storage-dns'
  parent: storagePrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobDnsZoneId
        }
      }
    ]
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-foundry-keyvault'
  location: location
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

resource keyVaultDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  name: 'keyvault-dns'
  parent: keyVaultPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyvault'
        properties: {
          privateDnsZoneId: keyVaultDnsZoneId
        }
      }
    ]
  }
}

output foundryPrivateEndpointId string = foundryPrivateEndpoint.id
// The conditional resource above is guaranteed to exist when this output is read because
// createStoragePrivateEndpoint gates both the resource and any caller's use of this output.
#disable-next-line BCP318
output storagePrivateEndpointId string = createStoragePrivateEndpoint ? storagePrivateEndpoint.id : ''
output keyVaultPrivateEndpointId string = keyVaultPrivateEndpoint.id

resource cosmosDBPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createCosmosDBPrivateEndpoint) {
  name: 'pe-foundry-cosmosdb'
  location: location
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

resource cosmosDBDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (createCosmosDBPrivateEndpoint) {
  name: 'cosmosdb-dns'
  parent: cosmosDBPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmosdb'
        properties: {
          privateDnsZoneId: cosmosDBDnsZoneId
        }
      }
    ]
  }
}

resource aiSearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (createAISearchPrivateEndpoint) {
  name: 'pe-foundry-aisearch'
  location: location
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

resource aiSearchDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (createAISearchPrivateEndpoint) {
  name: 'aisearch-dns'
  parent: aiSearchPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'aisearch'
        properties: {
          privateDnsZoneId: aiSearchDnsZoneId
        }
      }
    ]
  }
}

// The conditional resources above are guaranteed to exist when these outputs are read because
// createCosmosDBPrivateEndpoint/createAISearchPrivateEndpoint gate both the resource and any
// caller's use of the corresponding output.
#disable-next-line BCP318
output cosmosDBPrivateEndpointId string = createCosmosDBPrivateEndpoint ? cosmosDBPrivateEndpoint.id : ''
#disable-next-line BCP318
output aiSearchPrivateEndpointId string = createAISearchPrivateEndpoint ? aiSearchPrivateEndpoint.id : ''

