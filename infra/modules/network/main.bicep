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

@description('APIM NSG name.')
param apimNsgName string = 'nsg-apim'

@description('Compute NSG name.')
param computeNsgName string = 'nsg-compute'

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

resource snetApim 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: 'snet-apim'
  parent: vnet
  properties: {
    addressPrefix: apimSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
    networkSecurityGroup: {
      id: nsg.outputs.apimNsgId
    }
  }
}

resource snetFoundry 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: 'snet-foundry'
  parent: vnet
  properties: {
    addressPrefix: foundrySubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
    delegations: [
      {
        name: 'foundry-delegation'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource snetCompute 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: 'snet-compute'
  parent: vnet
  properties: {
    addressPrefix: computeSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
    networkSecurityGroup: {
      id: nsg.outputs.computeNsgId
    }
  }
}

resource snetPrivateEndpoints 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: 'snet-privateendpoints'
  parent: vnet
  properties: {
    addressPrefix: privateEndpointsSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource snetCicdAgents 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: 'snet-cicd-agents'
  parent: vnet
  properties: {
    addressPrefix: cicdAgentsSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
  }
}

resource azureBastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: 'AzureBastionSubnet'
  parent: vnet
  properties: {
    addressPrefix: bastionSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
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

output subnetIds object = {
  apim: snetApim.id
  foundry: snetFoundry.id
  compute: snetCompute.id
  privateEndpoints: snetPrivateEndpoints.id
  cicdAgents: snetCicdAgents.id
  bastion: azureBastionSubnet.id
}

output nsgIds object = {
  apim: nsg.outputs.apimNsgId
  compute: nsg.outputs.computeNsgId
}

output privateDnsZoneIds object = privateDns.outputs.zoneIds
