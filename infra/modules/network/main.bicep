targetScope = 'resourceGroup'

@description('Deployment location.')
param location string = resourceGroup().location

@description('VNet name.')
param vnetName string = 'vnet-agent-factory-poc'

@description('VNet address space.')
param vnetAddressSpace string = '10.0.0.0/16'

@description('APIM subnet CIDR.')
param apimSubnetPrefix string = '10.0.1.0/24'

@description('Foundry delegated subnet CIDR.')
param foundrySubnetPrefix string = '10.0.2.0/24'

@description('Compute subnet CIDR.')
param computeSubnetPrefix string = '10.0.3.0/24'

@description('Private endpoint subnet CIDR.')
param privateEndpointsSubnetPrefix string = '10.0.4.0/24'

@description('CI/CD agents subnet CIDR.')
param cicdAgentsSubnetPrefix string = '10.0.5.0/24'

@description('Bastion subnet CIDR (AzureBastionSubnet requires at least /26).')
param bastionSubnetPrefix string = '10.0.6.0/26'

@description('APIM NSG name. Mirrors the customer VPCx hybrid-NSG convention (hybrid-nsg-{subscription_name}-{region}), scoped per-subnet since APIM and compute have distinct rule sets.')
param apimNsgName string = 'hybrid-nsg-agent-blueprint-eastus2-apim'

@description('Compute NSG name. Mirrors the customer VPCx hybrid-NSG convention (hybrid-nsg-{subscription_name}-{region}), scoped per-subnet since APIM and compute have distinct rule sets.')
param computeNsgName string = 'hybrid-nsg-agent-blueprint-eastus2-compute'

@description('Private DNS zone names required for private endpoints.')
param privateDnsZoneNames object

module nsg './nsg.bicep' = {
  name: '${vnetName}-nsg'
  params: {
    location: location
    apimNsgName: apimNsgName
    computeNsgName: computeNsgName
    apimSubnetPrefix: apimSubnetPrefix
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
  }
}

// Subnet definitions are shared with the brownfield entry point via ./subnets.bicep, so subnet
// shape (delegation, NSG association, private-endpoint policy) has a single implementation. The
// module also serializes the child writes with @batchSize(1); declaring these subnets in parallel
// here previously risked intermittent 409 Conflict responses from the platform.
//
// Ownership boundary: the VNet resource above is declared ONLY in this greenfield template. The
// shared module references the VNet as `existing` and writes nothing but its subnet children,
// which is what allows brownfield to reuse it against an admin-owned VNet.
var subnetDefinitions = [
  {
    name: 'hybridsubnet-apim'
    addressPrefix: apimSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
    nsgId: nsg.outputs.apimNsgId
  }
  {
    name: 'hybridsubnet-foundry'
    addressPrefix: foundrySubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
    delegationServiceName: 'Microsoft.App/environments'
  }
  {
    name: 'hybridsubnet-compute'
    addressPrefix: computeSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
    nsgId: nsg.outputs.computeNsgId
  }
  {
    name: 'hybridsubnet-privateendpoints'
    addressPrefix: privateEndpointsSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'hybridsubnet-cicdagents'
    addressPrefix: cicdAgentsSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
  }
  {
    name: 'AzureBastionSubnet'
    addressPrefix: bastionSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
  }
]

module subnets './subnets.bicep' = {
  name: '${vnetName}-subnets'
  params: {
    vnetName: vnet.name
    subnets: subnetDefinitions
  }
}

module privateDns './private-dns.bicep' = {
  name: '${vnetName}-private-dns'
  params: {
    vnetId: vnet.id
    vnetName: vnet.name
    privateDnsZoneNames: privateDnsZoneNames
  }
}

output vnetId string = vnet.id

// Index order matches subnetDefinitions above.
output subnetIds object = {
  apim: subnets.outputs.subnetIds[0]
  foundry: subnets.outputs.subnetIds[1]
  compute: subnets.outputs.subnetIds[2]
  privateEndpoints: subnets.outputs.subnetIds[3]
  cicdAgents: subnets.outputs.subnetIds[4]
  bastion: subnets.outputs.subnetIds[5]
}

output nsgIds object = {
  apim: nsg.outputs.apimNsgId
  compute: nsg.outputs.computeNsgId
}

output privateDnsZoneIds object = privateDns.outputs.zoneIds
