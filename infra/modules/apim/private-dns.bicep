targetScope = 'resourceGroup'

@description('Private DNS zone name for internal APIM hostnames.')
param privateDnsZoneName string = 'azure-api.net'

@description('Virtual network resource ID linked to the zone.')
param vnetId string

@description('Virtual network name used in link naming.')
param vnetName string

@description('A-record name for the APIM gateway host.')
param apimGatewayRecordName string

@description('APIM internal private IP addresses. Records are created when at least one IP is present.')
param apimPrivateIpAddresses array = []

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource privateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource apimGatewayRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = if (length(apimPrivateIpAddresses) > 0) {
  parent: privateDnsZone
  name: apimGatewayRecordName
  properties: {
    ttl: 300
    aRecords: [for ip in apimPrivateIpAddresses: {
      ipv4Address: ip
    }]
  }
}

output privateDnsZoneId string = privateDnsZone.id
output privateDnsLinkId string = privateDnsVnetLink.id
output apimGatewayFqdn string = '${apimGatewayRecordName}.${privateDnsZoneName}'
output apimGatewayRecordId string = length(apimPrivateIpAddresses) > 0 ? apimGatewayRecord.id : ''
output dnsReadiness object = {
  zone: 'deployed'
  link: 'deployed'
  record: length(apimPrivateIpAddresses) > 0 ? 'deployed' : 'pending'
  privateIpCount: length(apimPrivateIpAddresses)
  status: length(apimPrivateIpAddresses) > 0 ? 'deployed' : 'pending'
}
