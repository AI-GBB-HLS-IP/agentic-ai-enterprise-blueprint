targetScope = 'resourceGroup'

@description('Deployment location.')
param location string = resourceGroup().location

@description('Azure Bastion host name.')
param bastionName string = 'bas-agent-factory-poc'

@description('Azure Bastion public IP name.')
param publicIpName string = 'pip-agent-factory-bastion'

@description('Resource ID of the AzureBastionSubnet.')
param bastionSubnetId string

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

output bastionId string = bastion.id
output publicIpId string = bastionPublicIp.id
