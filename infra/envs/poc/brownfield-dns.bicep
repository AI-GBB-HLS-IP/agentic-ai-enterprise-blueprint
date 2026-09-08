targetScope = 'resourceGroup'

// DNS-owner entry point for brownfield deployments: links the existing VNet to the 8 required
// private DNS zones. Each link is deployed at the DNS zone resource-group scope
// (dnsResourceGroupName); this template never creates or modifies a zone — only VNet links, with
// registration always disabled.
//
// Fast-POC-pass scope (see issue #48): the deferred DNS preflight validator and what-if guard
// (specs/00-network-foundation/tasks.md T048-T049, T052-T053) will add cross-tenant/ownership
// and change-scope safety checks in a follow-up; until then, verify zone existence and
// ownership out of band before deploying.

@description('Resource group containing the existing private DNS zones. This template must be deployed scoped to this resource group.')
param dnsResourceGroupName string = resourceGroup().name

@description('Resource ID of the existing VNet to link.')
param vnetId string

@description('Existing VNet name, used to build a deterministic link name.')
param vnetName string

@description('Existing private DNS zone names required by Foundry and its supporting resources. Every zone must already exist in dnsResourceGroupName.')
param privateDnsZoneNames object = {
  cognitiveServices: 'privatelink.cognitiveservices.azure.com'
  azureOpenAI: 'privatelink.openai.azure.com'
  apim: 'privatelink.azure-api.net'
  keyVault: 'privatelink.vaultcore.azure.net'
  storageBlob: 'privatelink.blob.core.windows.net'
  sql: 'privatelink.database.windows.net'
  cosmosDB: 'privatelink.documents.azure.com'
  aiSearch: 'privatelink.search.windows.net'
}

module cognitiveServicesLink '../../modules/network/private-dns-link.bicep' = {
  scope: resourceGroup(dnsResourceGroupName)
  name: 'brownfield-link-cognitiveservices'
  params: {
    zoneName: privateDnsZoneNames.cognitiveServices
    vnetId: vnetId
    vnetName: vnetName
  }
}

module azureOpenAILink '../../modules/network/private-dns-link.bicep' = {
  scope: resourceGroup(dnsResourceGroupName)
  name: 'brownfield-link-openai'
  params: {
    zoneName: privateDnsZoneNames.azureOpenAI
    vnetId: vnetId
    vnetName: vnetName
  }
}

module apimLink '../../modules/network/private-dns-link.bicep' = {
  scope: resourceGroup(dnsResourceGroupName)
  name: 'brownfield-link-apim'
  params: {
    zoneName: privateDnsZoneNames.apim
    vnetId: vnetId
    vnetName: vnetName
  }
}

module keyVaultLink '../../modules/network/private-dns-link.bicep' = {
  scope: resourceGroup(dnsResourceGroupName)
  name: 'brownfield-link-keyvault'
  params: {
    zoneName: privateDnsZoneNames.keyVault
    vnetId: vnetId
    vnetName: vnetName
  }
}

module storageBlobLink '../../modules/network/private-dns-link.bicep' = {
  scope: resourceGroup(dnsResourceGroupName)
  name: 'brownfield-link-blob'
  params: {
    zoneName: privateDnsZoneNames.storageBlob
    vnetId: vnetId
    vnetName: vnetName
  }
}

module sqlLink '../../modules/network/private-dns-link.bicep' = {
  scope: resourceGroup(dnsResourceGroupName)
  name: 'brownfield-link-sql'
  params: {
    zoneName: privateDnsZoneNames.sql
    vnetId: vnetId
    vnetName: vnetName
  }
}

module cosmosDBLink '../../modules/network/private-dns-link.bicep' = {
  scope: resourceGroup(dnsResourceGroupName)
  name: 'brownfield-link-cosmosdb'
  params: {
    zoneName: privateDnsZoneNames.cosmosDB
    vnetId: vnetId
    vnetName: vnetName
  }
}

module aiSearchLink '../../modules/network/private-dns-link.bicep' = {
  scope: resourceGroup(dnsResourceGroupName)
  name: 'brownfield-link-aisearch'
  params: {
    zoneName: privateDnsZoneNames.aiSearch
    vnetId: vnetId
    vnetName: vnetName
  }
}

output linkIds object = {
  cognitiveServices: cognitiveServicesLink.outputs.linkId
  azureOpenAI: azureOpenAILink.outputs.linkId
  apim: apimLink.outputs.linkId
  keyVault: keyVaultLink.outputs.linkId
  storageBlob: storageBlobLink.outputs.linkId
  sql: sqlLink.outputs.linkId
  cosmosDB: cosmosDBLink.outputs.linkId
  aiSearch: aiSearchLink.outputs.linkId
}
