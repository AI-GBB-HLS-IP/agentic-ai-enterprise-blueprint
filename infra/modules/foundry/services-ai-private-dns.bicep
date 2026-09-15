targetScope = 'resourceGroup'

@description('Resource ID of the VNet to link to the private DNS zone.')
param vnetId string

@description('VNet name used to create a deterministic private DNS zone link name.')
param vnetName string

@description('Tags to apply to the private DNS zone and VNet link.')
param tags object

resource servicesAiDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.services.ai.azure.com'
  location: 'global'
  tags: tags
}

resource servicesAiDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: servicesAiDns
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

output zoneId string = servicesAiDns.id
