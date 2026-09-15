targetScope = 'resourceGroup'

// DNS-association entry point for the Foundry deployment. Deploy this only after the private
// endpoints exist. Each association module is scoped to the resource group identified by the
// endpoint's full ARM resource ID.

@description('Resource group containing the network foundation (vnet, subnets, private DNS zones). Defaults to this resource group for single-RG deployments.')
param networkResourceGroupName string = resourceGroup().name

@description('Private DNS integration mechanism. Use vnet-link for same-subscription zones linked to the VNet, or zone-group for existing zones referenced by private endpoints.')
@allowed([
  'vnet-link'
  'zone-group'
])
param dnsIntegrationMode string

@description('Subscription containing the private DNS zones. Required in zone-group mode. In vnet-link mode it must be empty or match the workload subscription.')
param dnsSubscriptionId string = ''

@description('Resource group containing the private DNS zones. Required in zone-group mode. In vnet-link mode it must be empty or match networkResourceGroupName.')
param dnsResourceGroupName string = ''

@description('Existing VNet name (used to create the vnet-link for the services-ai zone in vnet-link mode).')
param vnetName string = 'vnet-agent-factory-poc'

@description('Full ARM resource ID of the Foundry account private endpoint. Leave empty to skip association.')
param foundryPrivateEndpointId string = ''

@description('Full ARM resource ID of the Storage private endpoint. Leave empty to skip association.')
param storagePrivateEndpointId string = ''

@description('Full ARM resource ID of the Key Vault private endpoint. Leave empty to skip association.')
param keyVaultPrivateEndpointId string = ''

@description('Full ARM resource ID of the Cosmos DB private endpoint. Leave empty to skip association.')
param cosmosDBPrivateEndpointId string = ''

@description('Full ARM resource ID of the AI Search private endpoint. Leave empty to skip association.')
param aiSearchPrivateEndpointId string = ''

@description('Tags to apply to every taggable resource created by this deployment.')
param tags object = {
  'foundry-poc': 'true'
}

var effectiveDnsSubscriptionId = dnsIntegrationMode == 'zone-group'
  ? (empty(dnsSubscriptionId)
      ? fail('dnsSubscriptionId is required when dnsIntegrationMode is zone-group; it must not be inferred from the workload subscription.')
      : dnsSubscriptionId)
  : (empty(dnsSubscriptionId) || toLower(dnsSubscriptionId) == toLower(subscription().subscriptionId)
      ? subscription().subscriptionId
      : fail('dnsSubscriptionId must be empty or match the workload subscription when dnsIntegrationMode is vnet-link.'))

var effectiveDnsResourceGroupName = dnsIntegrationMode == 'zone-group'
  ? (empty(dnsResourceGroupName)
      ? fail('dnsResourceGroupName is required when dnsIntegrationMode is zone-group; it must not be inferred from the workload resource group.')
      : dnsResourceGroupName)
  : (empty(dnsResourceGroupName) || toLower(dnsResourceGroupName) == toLower(networkResourceGroupName)
      ? networkResourceGroupName
      : fail('dnsResourceGroupName must be empty or match networkResourceGroupName when dnsIntegrationMode is vnet-link.'))

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  name: vnetName
}

resource cognitiveServicesDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  name: 'privatelink.cognitiveservices.azure.com'
}

resource openAiDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.openai.azure.com'
}

// Not part of the existing network foundation; the unified Foundry account endpoint
// (services.ai.azure.com) requires this zone per the official BYO VNet private-link table.
module servicesAiDns '../../modules/foundry/services-ai-private-dns.bicep' = if (dnsIntegrationMode == 'vnet-link') {
  name: 'services-ai-private-dns'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    vnetId: vnet.id
    vnetName: vnetName
    tags: tags
  }
}

resource blobDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.blob.core.windows.net'
}

resource keyVaultDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  name: 'privatelink.vaultcore.azure.net'
}

resource documentsDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.documents.azure.com'
}

resource searchDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.search.windows.net'
}

var zoneGroupDnsResourceIds = {
  cognitiveServices: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', cognitiveServicesDns.name)
  openAi: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', openAiDns.name)
  servicesAi: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.services.ai.azure.com')
  blob: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', blobDns.name)
  keyVault: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', keyVaultDns.name)
  cosmosDB: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', documentsDns.name)
  aiSearch: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', searchDns.name)
}

var vnetLinkDnsResourceIds = {
  cognitiveServices: cognitiveServicesDns.id
  openAi: openAiDns.id
  #disable-next-line BCP318
  servicesAi: servicesAiDns.outputs.zoneId
  blob: blobDns.id
  keyVault: keyVaultDns.id
  cosmosDB: documentsDns.id
  aiSearch: searchDns.id
}

var privateDnsZoneIds = dnsIntegrationMode == 'zone-group'
  ? zoneGroupDnsResourceIds
  : vnetLinkDnsResourceIds

var createFoundryDnsGroup = !empty(foundryPrivateEndpointId)
var foundryPrivateEndpointParts = split(foundryPrivateEndpointId, '/')
var _validateFoundryPrivateEndpointId = !createFoundryDnsGroup || (((length(foundryPrivateEndpointParts) == 9) || (length(foundryPrivateEndpointParts) == 10 && empty(foundryPrivateEndpointParts[?9] ?? ''))) && empty(foundryPrivateEndpointParts[?0] ?? '') && toLower(foundryPrivateEndpointParts[?1] ?? '') == 'subscriptions' && !empty(foundryPrivateEndpointParts[?2] ?? '') && toLower(foundryPrivateEndpointParts[?3] ?? '') == 'resourcegroups' && !empty(foundryPrivateEndpointParts[?4] ?? '') && toLower(foundryPrivateEndpointParts[?5] ?? '') == 'providers' && toLower(foundryPrivateEndpointParts[?6] ?? '') == 'microsoft.network' && toLower(foundryPrivateEndpointParts[?7] ?? '') == 'privateendpoints' && !empty(foundryPrivateEndpointParts[?8] ?? ''))
  ? true
  : fail('foundryPrivateEndpointId must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.')
var foundryPrivateEndpointSubscriptionId = createFoundryDnsGroup && _validateFoundryPrivateEndpointId ? foundryPrivateEndpointParts[2] : subscription().subscriptionId
var foundryPrivateEndpointResourceGroupName = createFoundryDnsGroup && _validateFoundryPrivateEndpointId ? foundryPrivateEndpointParts[4] : resourceGroup().name
var foundryPrivateEndpointName = createFoundryDnsGroup && _validateFoundryPrivateEndpointId ? foundryPrivateEndpointParts[8] : ''

var createKeyVaultDnsGroup = !empty(keyVaultPrivateEndpointId)
var keyVaultPrivateEndpointParts = split(keyVaultPrivateEndpointId, '/')
var _validateKeyVaultPrivateEndpointId = !createKeyVaultDnsGroup || (((length(keyVaultPrivateEndpointParts) == 9) || (length(keyVaultPrivateEndpointParts) == 10 && empty(keyVaultPrivateEndpointParts[?9] ?? ''))) && empty(keyVaultPrivateEndpointParts[?0] ?? '') && toLower(keyVaultPrivateEndpointParts[?1] ?? '') == 'subscriptions' && !empty(keyVaultPrivateEndpointParts[?2] ?? '') && toLower(keyVaultPrivateEndpointParts[?3] ?? '') == 'resourcegroups' && !empty(keyVaultPrivateEndpointParts[?4] ?? '') && toLower(keyVaultPrivateEndpointParts[?5] ?? '') == 'providers' && toLower(keyVaultPrivateEndpointParts[?6] ?? '') == 'microsoft.network' && toLower(keyVaultPrivateEndpointParts[?7] ?? '') == 'privateendpoints' && !empty(keyVaultPrivateEndpointParts[?8] ?? ''))
  ? true
  : fail('keyVaultPrivateEndpointId must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.')
var keyVaultPrivateEndpointSubscriptionId = createKeyVaultDnsGroup && _validateKeyVaultPrivateEndpointId ? keyVaultPrivateEndpointParts[2] : subscription().subscriptionId
var keyVaultPrivateEndpointResourceGroupName = createKeyVaultDnsGroup && _validateKeyVaultPrivateEndpointId ? keyVaultPrivateEndpointParts[4] : resourceGroup().name
var keyVaultPrivateEndpointName = createKeyVaultDnsGroup && _validateKeyVaultPrivateEndpointId ? keyVaultPrivateEndpointParts[8] : ''

var createStorageDnsGroup = !empty(storagePrivateEndpointId)
var storagePrivateEndpointParts = split(storagePrivateEndpointId, '/')
var _validateStoragePrivateEndpointId = !createStorageDnsGroup || (((length(storagePrivateEndpointParts) == 9) || (length(storagePrivateEndpointParts) == 10 && empty(storagePrivateEndpointParts[?9] ?? ''))) && empty(storagePrivateEndpointParts[?0] ?? '') && toLower(storagePrivateEndpointParts[?1] ?? '') == 'subscriptions' && !empty(storagePrivateEndpointParts[?2] ?? '') && toLower(storagePrivateEndpointParts[?3] ?? '') == 'resourcegroups' && !empty(storagePrivateEndpointParts[?4] ?? '') && toLower(storagePrivateEndpointParts[?5] ?? '') == 'providers' && toLower(storagePrivateEndpointParts[?6] ?? '') == 'microsoft.network' && toLower(storagePrivateEndpointParts[?7] ?? '') == 'privateendpoints' && !empty(storagePrivateEndpointParts[?8] ?? ''))
  ? true
  : fail('storagePrivateEndpointId must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.')
var storagePrivateEndpointSubscriptionId = createStorageDnsGroup && _validateStoragePrivateEndpointId ? storagePrivateEndpointParts[2] : subscription().subscriptionId
var storagePrivateEndpointResourceGroupName = createStorageDnsGroup && _validateStoragePrivateEndpointId ? storagePrivateEndpointParts[4] : resourceGroup().name
var storagePrivateEndpointName = createStorageDnsGroup && _validateStoragePrivateEndpointId ? storagePrivateEndpointParts[8] : ''

var createCosmosDBDnsGroup = !empty(cosmosDBPrivateEndpointId)
var cosmosDBPrivateEndpointParts = split(cosmosDBPrivateEndpointId, '/')
var _validateCosmosDBPrivateEndpointId = !createCosmosDBDnsGroup || (((length(cosmosDBPrivateEndpointParts) == 9) || (length(cosmosDBPrivateEndpointParts) == 10 && empty(cosmosDBPrivateEndpointParts[?9] ?? ''))) && empty(cosmosDBPrivateEndpointParts[?0] ?? '') && toLower(cosmosDBPrivateEndpointParts[?1] ?? '') == 'subscriptions' && !empty(cosmosDBPrivateEndpointParts[?2] ?? '') && toLower(cosmosDBPrivateEndpointParts[?3] ?? '') == 'resourcegroups' && !empty(cosmosDBPrivateEndpointParts[?4] ?? '') && toLower(cosmosDBPrivateEndpointParts[?5] ?? '') == 'providers' && toLower(cosmosDBPrivateEndpointParts[?6] ?? '') == 'microsoft.network' && toLower(cosmosDBPrivateEndpointParts[?7] ?? '') == 'privateendpoints' && !empty(cosmosDBPrivateEndpointParts[?8] ?? ''))
  ? true
  : fail('cosmosDBPrivateEndpointId must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.')
var cosmosDBPrivateEndpointSubscriptionId = createCosmosDBDnsGroup && _validateCosmosDBPrivateEndpointId ? cosmosDBPrivateEndpointParts[2] : subscription().subscriptionId
var cosmosDBPrivateEndpointResourceGroupName = createCosmosDBDnsGroup && _validateCosmosDBPrivateEndpointId ? cosmosDBPrivateEndpointParts[4] : resourceGroup().name
var cosmosDBPrivateEndpointName = createCosmosDBDnsGroup && _validateCosmosDBPrivateEndpointId ? cosmosDBPrivateEndpointParts[8] : ''

var createAISearchDnsGroup = !empty(aiSearchPrivateEndpointId)
var aiSearchPrivateEndpointParts = split(aiSearchPrivateEndpointId, '/')
var _validateAISearchPrivateEndpointId = !createAISearchDnsGroup || (((length(aiSearchPrivateEndpointParts) == 9) || (length(aiSearchPrivateEndpointParts) == 10 && empty(aiSearchPrivateEndpointParts[?9] ?? ''))) && empty(aiSearchPrivateEndpointParts[?0] ?? '') && toLower(aiSearchPrivateEndpointParts[?1] ?? '') == 'subscriptions' && !empty(aiSearchPrivateEndpointParts[?2] ?? '') && toLower(aiSearchPrivateEndpointParts[?3] ?? '') == 'resourcegroups' && !empty(aiSearchPrivateEndpointParts[?4] ?? '') && toLower(aiSearchPrivateEndpointParts[?5] ?? '') == 'providers' && toLower(aiSearchPrivateEndpointParts[?6] ?? '') == 'microsoft.network' && toLower(aiSearchPrivateEndpointParts[?7] ?? '') == 'privateendpoints' && !empty(aiSearchPrivateEndpointParts[?8] ?? ''))
  ? true
  : fail('aiSearchPrivateEndpointId must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.')
var aiSearchPrivateEndpointSubscriptionId = createAISearchDnsGroup && _validateAISearchPrivateEndpointId ? aiSearchPrivateEndpointParts[2] : subscription().subscriptionId
var aiSearchPrivateEndpointResourceGroupName = createAISearchDnsGroup && _validateAISearchPrivateEndpointId ? aiSearchPrivateEndpointParts[4] : resourceGroup().name
var aiSearchPrivateEndpointName = createAISearchDnsGroup && _validateAISearchPrivateEndpointId ? aiSearchPrivateEndpointParts[8] : ''

module foundryDns '../../modules/foundry/private-endpoint-dns.bicep' = if (createFoundryDnsGroup && _validateFoundryPrivateEndpointId) {
  name: 'foundry-private-endpoint-dns'
  scope: resourceGroup(foundryPrivateEndpointSubscriptionId, foundryPrivateEndpointResourceGroupName)
  params: {
    privateEndpointName: foundryPrivateEndpointName
    dnsGroupName: 'foundry-dns'
    privateDnsZoneConfigs: [
      {
        name: 'cognitive-services'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.cognitiveServices
        }
      }
      {
        name: 'openai'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.openAi
        }
      }
      {
        name: 'services-ai'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.servicesAi
        }
      }
    ]
  }
}

module storageDns '../../modules/foundry/private-endpoint-dns.bicep' = if (createStorageDnsGroup && _validateStoragePrivateEndpointId) {
  name: 'storage-private-endpoint-dns'
  scope: resourceGroup(storagePrivateEndpointSubscriptionId, storagePrivateEndpointResourceGroupName)
  params: {
    privateEndpointName: storagePrivateEndpointName
    dnsGroupName: 'storage-dns'
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.blob
        }
      }
    ]
  }
}

module keyVaultDnsAssociation '../../modules/foundry/private-endpoint-dns.bicep' = if (createKeyVaultDnsGroup && _validateKeyVaultPrivateEndpointId) {
  name: 'keyvault-private-endpoint-dns'
  scope: resourceGroup(keyVaultPrivateEndpointSubscriptionId, keyVaultPrivateEndpointResourceGroupName)
  params: {
    privateEndpointName: keyVaultPrivateEndpointName
    dnsGroupName: 'keyvault-dns'
    privateDnsZoneConfigs: [
      {
        name: 'keyvault'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.keyVault
        }
      }
    ]
  }
}

module cosmosDBDns '../../modules/foundry/private-endpoint-dns.bicep' = if (createCosmosDBDnsGroup && _validateCosmosDBPrivateEndpointId) {
  name: 'cosmosdb-private-endpoint-dns'
  scope: resourceGroup(cosmosDBPrivateEndpointSubscriptionId, cosmosDBPrivateEndpointResourceGroupName)
  params: {
    privateEndpointName: cosmosDBPrivateEndpointName
    dnsGroupName: 'cosmosdb-dns'
    privateDnsZoneConfigs: [
      {
        name: 'cosmosdb'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.cosmosDB
        }
      }
    ]
  }
}

module aiSearchDns '../../modules/foundry/private-endpoint-dns.bicep' = if (createAISearchDnsGroup && _validateAISearchPrivateEndpointId) {
  name: 'aisearch-private-endpoint-dns'
  scope: resourceGroup(aiSearchPrivateEndpointSubscriptionId, aiSearchPrivateEndpointResourceGroupName)
  params: {
    privateEndpointName: aiSearchPrivateEndpointName
    dnsGroupName: 'aisearch-dns'
    privateDnsZoneConfigs: [
      {
        name: 'aisearch'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.aiSearch
        }
      }
    ]
  }
}

#disable-next-line BCP318
output foundryDnsGroupId string = createFoundryDnsGroup ? foundryDns.outputs.dnsGroupId : ''
#disable-next-line BCP318
output keyVaultDnsGroupId string = createKeyVaultDnsGroup ? keyVaultDnsAssociation.outputs.dnsGroupId : ''
#disable-next-line BCP318
output storageDnsGroupId string = createStorageDnsGroup ? storageDns.outputs.dnsGroupId : ''
#disable-next-line BCP318
output cosmosDBDnsGroupId string = createCosmosDBDnsGroup ? cosmosDBDns.outputs.dnsGroupId : ''
#disable-next-line BCP318
output aiSearchDnsGroupId string = createAISearchDnsGroup ? aiSearchDns.outputs.dnsGroupId : ''
