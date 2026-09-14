targetScope = 'resourceGroup'

@description('Name of the existing (admin-owned) VNet to add subnets to. This module references the VNet as `existing` only and never declares or writes its top-level properties (address space, DDoS plan, etc.) — it writes only the child subnet resources listed below.')
param vnetName string

@description('''Subnet definitions to create beneath the existing VNet. Each item is an object with:
- `name` (required): subnet name.
- `addressPrefix` (required): CIDR for this subnet, must fall inside the existing VNet's address space and not overlap any other subnet (verify this out of band before deploying; the fast-POC pass in this module does not validate overlap itself).
- `privateEndpointNetworkPolicies` (optional, default `'Enabled'`): set to `'Disabled'` for the private-endpoints subnet.
- `delegationServiceName` (optional): e.g. `Microsoft.App/environments` for the Foundry delegated subnet.
- `nsgId` (optional): full resource ID of an NSG (new or existing/approved) to associate.
- `routeTableId` (optional): full ARM resource ID of an existing, customer-managed route table to
  associate. Per FR-018, this module never creates or modifies the referenced route table — it
  only associates it, and only its resource-ID shape is validated.
- `serviceEndpoints` (optional): array of Azure service endpoint names (e.g.
  `Microsoft.AzureActiveDirectory`) to enable on this subnet. Per FR-018a, names are not validated
  against a fixed list — Azure Resource Manager rejects unsupported values at deployment time.
''')
param subnets array

var routeTableIdSegmentCount = 9
var routeTableProviderPath = '/providers/microsoft.network/routetables/'

// Validated per-subnet so a typo in one subnet's routeTableId fails deterministically before any
// subnet PUT, rather than after earlier subnets in the serialized batch have already been
// written. Mirrors the NSG-ID shape validation used elsewhere in the network modules.
var _validateRouteTableIds = [for subnet in subnets: empty(subnet.?routeTableId ?? '') || (startsWith(toLower(subnet.?routeTableId ?? ''), '/subscriptions/') && contains(toLower(subnet.?routeTableId ?? ''), '/resourcegroups/') && contains(toLower(subnet.?routeTableId ?? ''), routeTableProviderPath) && length(split(subnet.?routeTableId ?? '', '/')) == routeTableIdSegmentCount)
  ? true
  : fail('Each subnet\'s routeTableId must be empty or a full ARM resource ID for Microsoft.Network/routeTables with no trailing slash, for example /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/routeTables/<name>.')]

// Bicep only allows a for-expression as the direct value of a variable/resource/module/output
// declaration (BCP138), not nested inside a ternary inside union() inside another resource loop.
// Pre-computing each subnet's serviceEndpoints array here, indexed alongside `subnets`, keeps the
// resource loop below to a single-level union().
var _subnetServiceEndpoints = [for subnet in subnets: map(subnet.?serviceEndpoints ?? [], endpoint => {
  service: endpoint
})]

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

// @batchSize(1) serializes subnet writes: concurrent PUTs against sibling subnets on the same
// VNet routinely conflict in Azure (the platform serializes VNet child writes internally), so
// parallel Bicep deployment of this loop would intermittently fail with 409 Conflict.
@batchSize(1)
resource newSubnets 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = [for (subnet, i) in subnets: {
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
    } : {},
    (_validateRouteTableIds[i] && contains(subnet, 'routeTableId') && !empty(subnet.routeTableId)) ? {
      routeTable: {
        id: subnet.routeTableId
      }
    } : {},
    (contains(subnet, 'serviceEndpoints') && !empty(subnet.serviceEndpoints)) ? {
      serviceEndpoints: _subnetServiceEndpoints[i]
    } : {}
  )
}]

output subnetIds array = [for (subnet, i) in subnets: newSubnets[i].id]
