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

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
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

resource storageDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
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
output storagePrivateEndpointId string = storagePrivateEndpoint.id
output keyVaultPrivateEndpointId string = keyVaultPrivateEndpoint.id
