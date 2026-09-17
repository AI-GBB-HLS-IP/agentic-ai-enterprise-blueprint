targetScope = 'resourceGroup'

@description('Private DNS zone name for internal APIM hostnames.')
param privateDnsZoneName string = 'azure-api.net'

@description('Whether this module creates the private DNS zone, VNet link, and records.')
param deployPrivateDns bool = true

@description('Virtual network resource ID linked to the zone.')
param vnetId string

@description('Virtual network name used in link naming.')
param vnetName string

@description('A-record name for the APIM gateway host.')
param apimGatewayRecordName string

@description('APIM internal private IP addresses. Records are created when at least one IP is present.')
param apimPrivateIpAddresses array = []

@description('Additional internal-mode APIM endpoint subdomains that need their own A record alongside the gateway (developer portal, legacy portal, management API, SCM). Internal VNet-injected APIM exposes each of these as a distinct hostname under the same zone, all resolving to the same private IP(s).')
param additionalEndpointSubdomains array = [
  'developer'
  'portal'
  'management'
  'scm'
]

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployPrivateDns) {
  name: privateDnsZoneName
  location: 'global'
}

resource privateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployPrivateDns) {
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

resource apimGatewayRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = if (deployPrivateDns && length(apimPrivateIpAddresses) > 0) {
  parent: privateDnsZone
  name: apimGatewayRecordName
  properties: {
    ttl: 300
    aRecords: [for ip in apimPrivateIpAddresses: {
      ipv4Address: ip
    }]
  }
}

resource apimAdditionalEndpointRecords 'Microsoft.Network/privateDnsZones/A@2020-06-01' = [for subdomain in additionalEndpointSubdomains: if (deployPrivateDns && length(apimPrivateIpAddresses) > 0) {
  parent: privateDnsZone
  name: '${apimGatewayRecordName}.${subdomain}'
  properties: {
    ttl: 300
    aRecords: [for ip in apimPrivateIpAddresses: {
      ipv4Address: ip
    }]
  }
}]

output privateDnsZoneId string = deployPrivateDns ? privateDnsZone.id : ''
output privateDnsLinkId string = deployPrivateDns ? privateDnsVnetLink.id : ''
output apimGatewayFqdn string = '${apimGatewayRecordName}.${privateDnsZoneName}'
output apimGatewayRecordId string = deployPrivateDns && length(apimPrivateIpAddresses) > 0 ? apimGatewayRecord.id : ''
output additionalEndpointFqdns array = [for subdomain in additionalEndpointSubdomains: '${apimGatewayRecordName}.${subdomain}.${privateDnsZoneName}']
output dnsReadiness object = {
  mode: deployPrivateDns ? 'blueprint' : 'external'
  zone: deployPrivateDns ? 'deployed' : 'external'
  link: deployPrivateDns ? 'deployed' : 'external'
  record: !deployPrivateDns ? 'external-handoff-required' : (length(apimPrivateIpAddresses) > 0 ? 'deployed' : 'pending')
  additionalEndpointRecords: !deployPrivateDns ? 'external-handoff-required' : (length(apimPrivateIpAddresses) > 0 ? 'deployed' : 'pending')
  privateIpCount: length(apimPrivateIpAddresses)
  status: length(apimPrivateIpAddresses) > 0 ? 'deployed' : 'pending'
}
