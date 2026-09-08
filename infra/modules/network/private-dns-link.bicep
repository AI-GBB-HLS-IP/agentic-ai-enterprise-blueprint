targetScope = 'resourceGroup'

@description('Name of the existing private DNS zone to link. The zone must already exist in this deployment scope — this module creates a VNet link only and never creates or modifies the zone itself.')
param zoneName string

@description('Resource ID of the VNet to link.')
param vnetId string

@description('VNet name used to build a deterministic, idempotent link name.')
param vnetName string

resource zone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: zoneName
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: zone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    // Fixed false: this brownfield DNS-owner path only ever links an already-existing,
    // already-populated zone for private-endpoint resolution. Enabling registration would let
    // Azure auto-register VM/NIC records into a zone this deployment does not own.
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

output linkId string = link.id
