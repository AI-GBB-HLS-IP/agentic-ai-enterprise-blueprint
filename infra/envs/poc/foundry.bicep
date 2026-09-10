targetScope = 'resourceGroup'

param location string = resourceGroup().location

@description('Resource group containing the network foundation (vnet, subnets, private DNS zones). Defaults to this resource group for single-RG deployments.')
param networkResourceGroupName string = resourceGroup().name

@description('Private DNS integration mechanism. Use vnet-link for same-subscription zones linked to the VNet, or zone-group for existing zones referenced by private endpoints.')
@allowed([
  'vnet-link'
  'zone-group'
])
param dnsIntegrationMode string

@description('Subscription containing the existing private DNS zones. Used only in zone-group mode.')
param dnsSubscriptionId string = ''

@description('Resource group containing the existing private DNS zones. Used only in zone-group mode.')
param dnsResourceGroupName string = ''

param foundryAccountName string = 'foundry-agent-factory-poc'
param projectName string = 'prj-agent-factory-poc'
param projectDisplayName string = 'Agent Factory POC'
param storageAccountName string = 'stagentfactorypoc'
param keyVaultName string = 'kv-agent-factory-poc'
param aiSearchServiceName string = 'srch-agent-factory-poc'
param cosmosDBAccountName string = 'cosmos-agent-factory-poc'
param vnetName string = 'vnet-agent-factory-poc'
param foundrySubnetName string = 'hybridsubnet-foundry'
param privateEndpointSubnetName string = 'hybridsubnet-privateendpoints'

@description('Existing Storage account full ARM resource ID. Leave empty to create a new storage account.')
param existingAzureStorageAccountResourceId string = ''

@description('Set to true if the existing (BYO) storage account already has a private endpoint configured.')
param existingStoragePrivateEndpoint bool = false

@description('Existing AI Search service full ARM resource ID. Leave empty to create a new AI Search service.')
param existingAISearchResourceId string = ''

@description('Set to true if the existing (BYO) AI Search service already has a private endpoint configured.')
param existingAISearchPrivateEndpoint bool = false

@description('Existing Cosmos DB account full ARM resource ID. Leave empty to create a new Cosmos DB account.')
param existingAzureCosmosDBAccountResourceId string = ''

@description('Set to true if the existing (BYO) Cosmos DB account already has a private endpoint configured.')
param existingCosmosDBPrivateEndpoint bool = false

param enableModelDeployment bool = false
param modelDeploymentName string = 'gpt4.1-mini-poc'
param modelName string = 'gpt4.1-mini'
param modelVersion string = '__PENDING_APPROVAL__'
param modelFormat string = 'OpenAI'
param modelSkuName string = 'Standard'
param modelCapacity int = 10

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  name: vnetName
}

resource foundrySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: foundrySubnetName
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
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
}

resource servicesAiDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (dnsIntegrationMode == 'vnet-link') {
  parent: servicesAiDns
  name: '${vnetName}-link'
  location: 'global'
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

var _validateZoneGroupDnsScope = dnsIntegrationMode != 'zone-group' || (!empty(dnsSubscriptionId) && !empty(dnsResourceGroupName))
  ? true
  : fail('dnsSubscriptionId and dnsResourceGroupName are required when dnsIntegrationMode is zone-group.')

var dnsSubscriptionIdResolved = dnsIntegrationMode == 'zone-group'
  ? (_validateZoneGroupDnsScope ? dnsSubscriptionId : '')
  : subscription().subscriptionId
var dnsResourceGroupNameResolved = dnsIntegrationMode == 'zone-group'
  ? (_validateZoneGroupDnsScope ? dnsResourceGroupName : '')
  : networkResourceGroupName

var zoneGroupDnsResourceIds = {
  cognitiveServices: resourceId(dnsSubscriptionIdResolved, dnsResourceGroupNameResolved, 'Microsoft.Network/privateDnsZones', cognitiveServicesDns.name)
  openAi: resourceId(dnsSubscriptionIdResolved, dnsResourceGroupNameResolved, 'Microsoft.Network/privateDnsZones', openAiDns.name)
  servicesAi: resourceId(dnsSubscriptionIdResolved, dnsResourceGroupNameResolved, 'Microsoft.Network/privateDnsZones', servicesAiDns.name)
  blob: resourceId(dnsSubscriptionIdResolved, dnsResourceGroupNameResolved, 'Microsoft.Network/privateDnsZones', blobDns.name)
  keyVault: resourceId(dnsSubscriptionIdResolved, dnsResourceGroupNameResolved, 'Microsoft.Network/privateDnsZones', keyVaultDns.name)
  cosmosDB: resourceId(dnsSubscriptionIdResolved, dnsResourceGroupNameResolved, 'Microsoft.Network/privateDnsZones', documentsDns.name)
  aiSearch: resourceId(dnsSubscriptionIdResolved, dnsResourceGroupNameResolved, 'Microsoft.Network/privateDnsZones', searchDns.name)
}

var vnetLinkDnsResourceIds = {
  cognitiveServices: cognitiveServicesDns.id
  openAi: openAiDns.id
  servicesAi: servicesAiDns.id
  blob: blobDns.id
  keyVault: keyVaultDns.id
  cosmosDB: documentsDns.id
  aiSearch: searchDns.id
}

var privateDnsZoneIds = dnsIntegrationMode == 'zone-group'
  ? zoneGroupDnsResourceIds
  : vnetLinkDnsResourceIds

module foundry '../../modules/foundry/main.bicep' = {
  name: 'foundry-platform'
  params: {
    location: location
    foundryAccountName: foundryAccountName
    projectName: projectName
    projectDisplayName: projectDisplayName
    foundrySubnetId: foundrySubnet.id
    privateEndpointSubnetId: privateEndpointSubnet.id
    privateDnsZoneIds: privateDnsZoneIds
    storageAccountName: storageAccountName
    keyVaultName: keyVaultName
    aiSearchServiceName: aiSearchServiceName
    cosmosDBAccountName: cosmosDBAccountName
    existingAzureStorageAccountResourceId: existingAzureStorageAccountResourceId
    existingStoragePrivateEndpoint: existingStoragePrivateEndpoint
    existingAISearchResourceId: existingAISearchResourceId
    existingAISearchPrivateEndpoint: existingAISearchPrivateEndpoint
    existingAzureCosmosDBAccountResourceId: existingAzureCosmosDBAccountResourceId
    existingCosmosDBPrivateEndpoint: existingCosmosDBPrivateEndpoint
    enableModelDeployment: enableModelDeployment
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelVersion: modelVersion
    modelFormat: modelFormat
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
  }
}

output foundryAccountId string = foundry.outputs.foundryAccountId
output foundryProjectId string = foundry.outputs.foundryProjectId
output storageAccountId string = foundry.outputs.storageAccountId
output keyVaultId string = foundry.outputs.keyVaultId
output aiSearchServiceId string = foundry.outputs.aiSearchServiceId
output cosmosDBAccountId string = foundry.outputs.cosmosDBAccountId
output capabilityHostId string = foundry.outputs.capabilityHostId
