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

module network '../../modules/network/main.bicep' = {
  name: 'network-foundation'
  params: {
    location: location
    vnetName: vnetName
    vnetAddressSpace: vnetAddressSpace
    apimSubnetPrefix: apimSubnetPrefix
    foundrySubnetPrefix: foundrySubnetPrefix
    computeSubnetPrefix: computeSubnetPrefix
    privateEndpointsSubnetPrefix: privateEndpointsSubnetPrefix
    cicdAgentsSubnetPrefix: cicdAgentsSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    apimNsgName: apimNsgName
    computeNsgName: computeNsgName
    privateDnsZoneNames: privateDnsZoneNames
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
