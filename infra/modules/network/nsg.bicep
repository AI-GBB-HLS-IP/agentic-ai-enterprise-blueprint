targetScope = 'resourceGroup'

@description('Deployment location for NSGs.')
param location string = resourceGroup().location

@description('Name of the APIM subnet NSG.')
param apimNsgName string = 'nsg-apim'

@description('Name of the compute subnet NSG.')
param computeNsgName string = 'nsg-compute'

@description('APIM subnet prefix used by compute outbound allow rule.')
param apimSubnetPrefix string = '10.0.1.0/24'

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: apimNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-ApiManagement-ControlPlane-3443-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-APIM-Outbound-Internet-443'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
        }
      }
    ]
  }
}

resource computeNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: computeNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-Compute-To-APIM-443-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: apimSubnetPrefix
        }
      }
      {
        name: 'Allow-Compute-VNet-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Deny-Compute-Internet-Outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
        }
      }
    ]
  }
}

output apimNsgId string = apimNsg.id
output computeNsgId string = computeNsg.id
