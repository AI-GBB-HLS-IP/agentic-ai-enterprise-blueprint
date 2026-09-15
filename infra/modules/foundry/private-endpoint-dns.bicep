// Creates the privateDnsZoneGroups child resource for each already-created Foundry private
// endpoint. This is the Bicep equivalent of the tenant's manual Phase 3 Portal step (see
// ../../../openspec/changes/foundry-staged-private-endpoint-deployment/design.md): every private
// endpoint referenced here must already exist (created by ./private-endpoint.bicep or an
// equivalent prior deployment) before this template runs. Each *PrivateEndpointName parameter
// defaults to empty, which skips creating a DNS zone group for that resource (e.g. because no
// private endpoint was created for a BYO resource that already had one).

@description('Name of the already-existing Foundry account private endpoint.')
param foundryPrivateEndpointName string

@description('Cognitive Services private DNS zone resource ID.')
param cognitiveServicesDnsZoneId string

@description('Azure OpenAI private DNS zone resource ID.')
param openAiDnsZoneId string

@description('Foundry services-ai private DNS zone resource ID.')
param servicesAiDnsZoneId string

@description('Name of the already-existing Storage private endpoint. Leave empty to skip.')
param storagePrivateEndpointName string = ''

@description('Storage blob private DNS zone resource ID. Required when storagePrivateEndpointName is set.')
param blobDnsZoneId string = ''

@description('Name of the already-existing Key Vault private endpoint.')
param keyVaultPrivateEndpointName string

@description('Key Vault private DNS zone resource ID.')
param keyVaultDnsZoneId string

@description('Name of the already-existing Cosmos DB private endpoint. Leave empty to skip.')
param cosmosDBPrivateEndpointName string = ''

@description('Cosmos DB private DNS zone resource ID. Required when cosmosDBPrivateEndpointName is set.')
param cosmosDBDnsZoneId string = ''

@description('Name of the already-existing AI Search private endpoint. Leave empty to skip.')
param aiSearchPrivateEndpointName string = ''

@description('AI Search private DNS zone resource ID. Required when aiSearchPrivateEndpointName is set.')
param aiSearchDnsZoneId string = ''

var createStorageDnsGroup = !empty(storagePrivateEndpointName)
var createCosmosDBDnsGroup = !empty(cosmosDBPrivateEndpointName)
var createAISearchDnsGroup = !empty(aiSearchPrivateEndpointName)

var _validateStorageDnsInputs = createStorageDnsGroup && empty(blobDnsZoneId) ? fail('blobDnsZoneId is required when storagePrivateEndpointName is set.') : true
var _validateCosmosDnsInputs = createCosmosDBDnsGroup && empty(cosmosDBDnsZoneId) ? fail('cosmosDBDnsZoneId is required when cosmosDBPrivateEndpointName is set.') : true
var _validateAISearchDnsInputs = createAISearchDnsGroup && empty(aiSearchDnsZoneId) ? fail('aiSearchDnsZoneId is required when aiSearchPrivateEndpointName is set.') : true

resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = {
  name: foundryPrivateEndpointName
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

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = if (createStorageDnsGroup) {
  name: storagePrivateEndpointName
}

resource storageDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (createStorageDnsGroup && _validateStorageDnsInputs) {
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

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = {
  name: keyVaultPrivateEndpointName
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

resource cosmosDBPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = if (createCosmosDBDnsGroup) {
  name: cosmosDBPrivateEndpointName
}

resource cosmosDBDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (createCosmosDBDnsGroup && _validateCosmosDnsInputs) {
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

resource aiSearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = if (createAISearchDnsGroup) {
  name: aiSearchPrivateEndpointName
}

resource aiSearchDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (createAISearchDnsGroup && _validateAISearchDnsInputs) {
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

output foundryDnsGroupId string = foundryDnsGroup.id
output keyVaultDnsGroupId string = keyVaultDnsGroup.id
// The conditional resources above are guaranteed to exist when these outputs are read because
// createStorageDnsGroup/createCosmosDBDnsGroup/createAISearchDnsGroup gate both the resource and
// any caller's use of the corresponding output.
#disable-next-line BCP318
output storageDnsGroupId string = createStorageDnsGroup ? storageDnsGroup.id : ''
#disable-next-line BCP318
output cosmosDBDnsGroupId string = createCosmosDBDnsGroup ? cosmosDBDnsGroup.id : ''
#disable-next-line BCP318
output aiSearchDnsGroupId string = createAISearchDnsGroup ? aiSearchDnsGroup.id : ''
