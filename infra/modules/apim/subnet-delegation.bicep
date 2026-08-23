targetScope = 'resourceGroup'

@description('Name of the existing virtual network that hosts the APIM subnet.')
param vnetName string

@description('Name of the APIM subnet to delegate.')
param apimSubnetName string = 'snet-apim'

@description('Expected APIM subnet prefix. This module does not mutate the CIDR.')
param apimSubnetPrefix string = '10.0.1.0/24'

@description('Existing NSG resource ID associated with snet-apim.')
param apimSubnetNsgId string

@description('Delegation name for Premium v2 APIM VNet injection.')
param delegationName string = 'apim-premiumv2-delegation'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

// Re-declare the existing subnet with the required Premium v2 delegation while preserving
// the existing subnet CIDR and NSG association from the network foundation.
resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: apimSubnetName
  properties: {
    addressPrefix: apimSubnetPrefix
    privateEndpointNetworkPolicies: 'Enabled'
    networkSecurityGroup: {
      id: apimSubnetNsgId
    }
    delegations: [
      {
        name: delegationName
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

output subnetId string = apimSubnet.id
output subnetPrefix string = apimSubnet.properties.addressPrefix
output nsgId string = apimSubnet.properties.networkSecurityGroup.id
output delegationApplied bool = true
output subnetDelegationState object = {
  subnetName: apimSubnet.name
  subnetPrefix: apimSubnet.properties.addressPrefix
  nsgId: apimSubnet.properties.networkSecurityGroup.id
  delegationServiceNames: [
    'Microsoft.Web/serverFarms'
  ]
  status: 'deployed'
}
