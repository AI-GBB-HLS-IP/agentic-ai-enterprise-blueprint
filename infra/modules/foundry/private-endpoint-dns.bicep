targetScope = 'resourceGroup'

// Creates one privateDnsZoneGroups child resource for an already-created private endpoint.
// Callers scope this module to the resource group parsed from the endpoint's full ARM resource ID.

@description('Name of the already-existing private endpoint in this module deployment scope.')
param privateEndpointName string

@description('Name of the private DNS zone group.')
param dnsGroupName string

@description('Private DNS zone configurations to associate with the endpoint.')
param privateDnsZoneConfigs array

var _validatePrivateEndpointName = !empty(privateEndpointName)
  ? true
  : fail('privateEndpointName must not be empty.')
var _validateDnsGroupName = !empty(dnsGroupName)
  ? true
  : fail('dnsGroupName must not be empty.')
var _validatePrivateDnsZoneConfigs = !empty(privateDnsZoneConfigs)
  ? true
  : fail('privateDnsZoneConfigs must contain at least one private DNS zone configuration.')

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' existing = {
  name: _validatePrivateEndpointName ? privateEndpointName : ''
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  name: _validateDnsGroupName ? dnsGroupName : ''
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: _validatePrivateDnsZoneConfigs ? privateDnsZoneConfigs : []
  }
}

output dnsGroupId string = dnsGroup.id
