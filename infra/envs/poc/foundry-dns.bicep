targetScope = 'resourceGroup'

// DNS-association ("Phase 3") entry point for the Foundry deployment. Deploy this only after
// ./foundry.bicep's private endpoints already exist; it creates the privateDnsZoneGroups child
// resource for each one. This is the templated equivalent of the tenant's manual, per-resource
// Azure Portal step (see ../../../openspec/changes/foundry-staged-private-endpoint-deployment
// for the rationale). Must be deployed scoped to the same resource group as ./foundry.bicep,
// since private endpoints and their DNS zone groups are not cross-resource-group resources.

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

@description('Name of the Foundry account private endpoint created by foundry.bicep.')
param foundryPrivateEndpointName string

@description('Name of the Storage private endpoint created by foundry.bicep. Leave empty to skip (e.g. BYO storage that already had a private endpoint).')
param storagePrivateEndpointName string = ''

@description('Name of the Key Vault private endpoint created by foundry.bicep.')
param keyVaultPrivateEndpointName string

@description('Name of the Cosmos DB private endpoint created by foundry.bicep. Leave empty to skip.')
param cosmosDBPrivateEndpointName string = ''

@description('Name of the AI Search private endpoint created by foundry.bicep. Leave empty to skip.')
param aiSearchPrivateEndpointName string = ''

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
resource servicesAiDns 'Microsoft.Network/privateDnsZones@2020-06-01' = if (dnsIntegrationMode == 'vnet-link') {
  name: 'privatelink.services.ai.azure.com'
  location: 'global'
  tags: tags
}

resource servicesAiDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (dnsIntegrationMode == 'vnet-link') {
  parent: servicesAiDns
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
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
  #disable-next-line BCP318
  servicesAi: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', servicesAiDns.name)
  blob: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', blobDns.name)
  keyVault: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', keyVaultDns.name)
  cosmosDB: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', documentsDns.name)
  aiSearch: resourceId(effectiveDnsSubscriptionId, effectiveDnsResourceGroupName, 'Microsoft.Network/privateDnsZones', searchDns.name)
}

var vnetLinkDnsResourceIds = {
  cognitiveServices: cognitiveServicesDns.id
  openAi: openAiDns.id
  #disable-next-line BCP318
  servicesAi: servicesAiDns.id
  blob: blobDns.id
  keyVault: keyVaultDns.id
  cosmosDB: documentsDns.id
  aiSearch: searchDns.id
}

var privateDnsZoneIds = dnsIntegrationMode == 'zone-group'
  ? zoneGroupDnsResourceIds
  : vnetLinkDnsResourceIds

module foundryDns '../../modules/foundry/private-endpoint-dns.bicep' = {
  name: 'foundry-private-endpoint-dns'
  params: {
    foundryPrivateEndpointName: foundryPrivateEndpointName
    cognitiveServicesDnsZoneId: privateDnsZoneIds.cognitiveServices
    openAiDnsZoneId: privateDnsZoneIds.openAi
    servicesAiDnsZoneId: privateDnsZoneIds.servicesAi
    storagePrivateEndpointName: storagePrivateEndpointName
    blobDnsZoneId: privateDnsZoneIds.blob
    keyVaultPrivateEndpointName: keyVaultPrivateEndpointName
    keyVaultDnsZoneId: privateDnsZoneIds.keyVault
    cosmosDBPrivateEndpointName: cosmosDBPrivateEndpointName
    cosmosDBDnsZoneId: privateDnsZoneIds.cosmosDB
    aiSearchPrivateEndpointName: aiSearchPrivateEndpointName
    aiSearchDnsZoneId: privateDnsZoneIds.aiSearch
  }
}

output foundryDnsGroupId string = foundryDns.outputs.foundryDnsGroupId
output storageDnsGroupId string = foundryDns.outputs.storageDnsGroupId
output keyVaultDnsGroupId string = foundryDns.outputs.keyVaultDnsGroupId
output cosmosDBDnsGroupId string = foundryDns.outputs.cosmosDBDnsGroupId
output aiSearchDnsGroupId string = foundryDns.outputs.aiSearchDnsGroupId
