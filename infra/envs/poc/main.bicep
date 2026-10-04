targetScope = 'resourceGroup'

@description('Deployment location (defaults to resource group location).')
param location string = resourceGroup().location

@description('VNet name for the POC environment.')
param vnetName string = 'vnet-agent-factory-poc'

@description('VNet CIDR.')
param vnetAddressSpace string = '10.0.0.0/16'

@description('APIM subnet CIDR.')
param apimSubnetPrefix string = '10.0.1.0/24'

@description('Foundry subnet CIDR.')
param foundrySubnetPrefix string = '10.0.2.0/24'

@description('''Service endpoints to enable on the Foundry agent subnet. Defaults to none,
matching FR-018a (no service endpoints except on the APIM-purpose subnet); pass
`['Microsoft.CognitiveServices']` explicitly where an enterprise network-governance policy
requires it.''')
param foundryServiceEndpoints array = []

@description('Compute subnet CIDR.')
param computeSubnetPrefix string = '10.0.3.0/24'

@description('Private endpoints subnet CIDR.')
param privateEndpointsSubnetPrefix string = '10.0.4.0/24'

@description('CI/CD agents subnet CIDR.')
param cicdAgentsSubnetPrefix string = '10.0.5.0/24'

@description('Bastion subnet CIDR.')
param bastionSubnetPrefix string = '10.0.6.0/26'

@description('Azure Bastion host name.')
param bastionName string = 'bas-agent-factory-poc'

@description('Azure Bastion public IP name.')
param bastionPublicIpName string = 'pip-agent-factory-bastion'

@description('APIM NSG name.')
param apimNsgName string = 'nsg-apim'

@description('Compute NSG name.')
param computeNsgName string = 'nsg-compute'

@description('Private DNS zone names.')
param privateDnsZoneNames object

@description('Tags for the blueprint-created virtual network.')
param virtualNetworkTags object = {}

@description('Tags for the blueprint-created APIM NSG.')
param apimNsgTags object = {}

@description('Tags for the blueprint-created compute NSG.')
param computeNsgTags object = {}

@description('Purpose-keyed tags for blueprint-created private DNS zones.')
param privateDnsZoneTags object = {}

@description('Purpose-keyed tags for blueprint-created private DNS virtual network links.')
param privateDnsVnetLinkTags object = {}

module network '../../modules/network/main.bicep' = {
  name: 'network-foundation'
  params: {
    location: location
    vnetName: vnetName
    vnetAddressSpace: vnetAddressSpace
    apimSubnetPrefix: apimSubnetPrefix
    foundrySubnetPrefix: foundrySubnetPrefix
    foundryServiceEndpoints: foundryServiceEndpoints
    computeSubnetPrefix: computeSubnetPrefix
    privateEndpointsSubnetPrefix: privateEndpointsSubnetPrefix
    cicdAgentsSubnetPrefix: cicdAgentsSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    apimNsgName: apimNsgName
    computeNsgName: computeNsgName
    privateDnsZoneNames: privateDnsZoneNames
    virtualNetworkTags: virtualNetworkTags
    apimNsgTags: apimNsgTags
    computeNsgTags: computeNsgTags
    privateDnsZoneTags: privateDnsZoneTags
    privateDnsVnetLinkTags: privateDnsVnetLinkTags
  }
}

module bastion '../../modules/network/bastion.bicep' = {
  name: 'network-bastion'
  params: {
    location: location
    bastionName: bastionName
    publicIpName: bastionPublicIpName
    bastionSubnetId: network.outputs.subnetIds.bastion
  }
}

output vnetId string = network.outputs.vnetId
output subnetIds object = network.outputs.subnetIds
output nsgIds object = network.outputs.nsgIds
output privateDnsZoneIds object = network.outputs.privateDnsZoneIds
output bastionId string = bastion.outputs.bastionId
output bastionPublicIpId string = bastion.outputs.publicIpId
