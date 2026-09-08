targetScope = 'resourceGroup'

@description('Name of the existing (admin-owned) VNet to add subnets to. This module references the VNet as `existing` only and never declares or writes its top-level properties (address space, DDoS plan, etc.) — it writes only the child subnet resources listed below.')
param vnetName string

@description('''Subnet definitions to create beneath the existing VNet. Each item is an object with:
- `name` (required): subnet name.
- `addressPrefix` (required): CIDR for this subnet, must fall inside the existing VNet's address space and not overlap any other subnet (verify this out of band before deploying; the fast-POC pass in this module does not validate overlap itself).
- `privateEndpointNetworkPolicies` (optional, default `'Enabled'`): set to `'Disabled'` for the private-endpoints subnet.
- `delegationServiceName` (optional): e.g. `Microsoft.App/environments` for the Foundry delegated subnet.
- `nsgId` (optional): full resource ID of an NSG (new or existing/approved) to associate.
''')
param subnets array

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

// @batchSize(1) serializes subnet writes: concurrent PUTs against sibling subnets on the same
// VNet routinely conflict in Azure (the platform serializes VNet child writes internally), so
// parallel Bicep deployment of this loop would intermittently fail with 409 Conflict.
@batchSize(1)
resource newSubnets 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = [for subnet in subnets: {
  parent: vnet
  name: subnet.name
  properties: union(
    {
      addressPrefix: subnet.addressPrefix
      privateEndpointNetworkPolicies: contains(subnet, 'privateEndpointNetworkPolicies') ? subnet.privateEndpointNetworkPolicies : 'Enabled'
    },
    contains(subnet, 'delegationServiceName') ? {
      delegations: [
        {
          name: '${subnet.name}-delegation'
          properties: {
            serviceName: subnet.delegationServiceName
          }
        }
      ]
    } : {},
    contains(subnet, 'nsgId') ? {
      networkSecurityGroup: {
        id: subnet.nsgId
      }
    } : {}
  )
}]

output subnetIds array = [for (subnet, i) in subnets: newSubnets[i].id]
