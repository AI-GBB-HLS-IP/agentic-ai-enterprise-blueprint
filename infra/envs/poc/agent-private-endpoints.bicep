targetScope = 'resourceGroup'

@description('Private endpoint location.')
param location string = resourceGroup().location

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

@description('Approved, owner-managed AMPLS private endpoint ID. This stage only references it.')
param approvedAmplsPrivateEndpointId string

@description('Approved Azure Monitor Private Link Scope resource ID targeted by the supplied AMPLS endpoint.')
param approvedAmplsResourceId string

@description('Tags applied only to newly created private endpoints.')
param tags object = {}

module privateEndpoints '../../modules/agent/shared-private-endpoints.bicep' = {
  name: 'phase1-agent-private-endpoints'
  params: {
    location: location
    privateEndpointSubnetId: privateEndpointSubnetId
    storageAccountId: storageAccountId
    keyVaultId: keyVaultId
    cosmosDBAccountId: cosmosDBAccountId
    aiSearchServiceId: aiSearchServiceId
    createStoragePrivateEndpoint: createStoragePrivateEndpoint
    storagePrivateEndpointId: storagePrivateEndpointId
    createKeyVaultPrivateEndpoint: createKeyVaultPrivateEndpoint
    keyVaultPrivateEndpointId: keyVaultPrivateEndpointId
    createCosmosDBPrivateEndpoint: createCosmosDBPrivateEndpoint
    cosmosDBPrivateEndpointId: cosmosDBPrivateEndpointId
    createAISearchPrivateEndpoint: createAISearchPrivateEndpoint
    aiSearchPrivateEndpointId: aiSearchPrivateEndpointId
    approvedAmplsPrivateEndpointId: approvedAmplsPrivateEndpointId
    approvedAmplsResourceId: approvedAmplsResourceId
    tags: tags
  }
}

output storagePrivateEndpointId string = privateEndpoints.outputs.storagePrivateEndpointId
output keyVaultPrivateEndpointId string = privateEndpoints.outputs.keyVaultPrivateEndpointId
output cosmosDBPrivateEndpointId string = privateEndpoints.outputs.cosmosDBPrivateEndpointId
output aiSearchPrivateEndpointId string = privateEndpoints.outputs.aiSearchPrivateEndpointId
output amplsPrivateEndpointId string = privateEndpoints.outputs.amplsPrivateEndpointId
