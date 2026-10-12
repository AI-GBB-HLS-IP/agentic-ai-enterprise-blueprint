targetScope = 'resourceGroup'

import { endpointMatrixValid, customHostnamesValid, endpointEvidenceValid, endpointEvidencePassed } from './endpoints.bicep'

@allowed(['built-in', 'custom'])
param endpointMode string = 'built-in'

@allowed(['direct-private', 'corporate-routed'])
param endpointAccessPath string = 'direct-private'

param customEndpointHostnames object = {}
param apimServiceId string = ''
param endpointValidationEvidence object = {}

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

@description('Tags applied to the blueprint-owned APIM private DNS zone.')
param privateDnsZoneTags object = {}

@description('Tags applied to the blueprint-owned APIM private DNS virtual network link.')
param privateDnsVnetLinkTags object = {}

@description('Non-secret evidence reference recorded only after external APIM DNS resolution and reachability are validated.')
param externalDnsValidationReference string = ''

@description('Additional internal-mode APIM endpoint subdomains that need their own A record alongside the gateway (developer portal, legacy portal, management API, SCM). Internal VNet-injected APIM exposes each of these as a distinct hostname under the same zone, all resolving to the same private IP(s).')
param additionalEndpointSubdomains array = [
  'developer'
  'portal'
  'management'
  'scm'
]

var endpointConfigurationValidated = endpointMatrixValid(endpointMode, endpointAccessPath, deployPrivateDns ? 'blueprint' : 'external') && (endpointMode != 'custom' || customHostnamesValid(customEndpointHostnames))
  ? true
  : fail('Custom endpoints require external DNS and three valid custom hostnames; corporate routing requires custom/external.')
var endpointEvidenceValidated = empty(endpointValidationEvidence) || (endpointMode == 'custom' && endpointEvidenceValid(endpointValidationEvidence, apimServiceId, endpointMode, endpointAccessPath, customEndpointHostnames))
  ? true
  : fail('Invalid endpointValidationEvidence: require all base/extension fields and matching endpoint context.')
var customEndpointsReady = endpointEvidenceValidated && endpointEvidencePassed(endpointValidationEvidence, apimServiceId, endpointMode, endpointAccessPath, customEndpointHostnames)
var deployValidatedPrivateDns = deployPrivateDns && endpointConfigurationValidated && endpointEvidenceValidated

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployValidatedPrivateDns) {
  name: privateDnsZoneName
  location: 'global'
  tags: privateDnsZoneTags
}

resource privateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployValidatedPrivateDns) {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: privateDnsVnetLinkTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource apimGatewayRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = if (deployValidatedPrivateDns && length(apimPrivateIpAddresses) > 0) {
  parent: privateDnsZone
  name: apimGatewayRecordName
  properties: {
    ttl: 300
    aRecords: [for ip in apimPrivateIpAddresses: {
      ipv4Address: ip
    }]
  }
}

resource apimAdditionalEndpointRecords 'Microsoft.Network/privateDnsZones/A@2020-06-01' = [for subdomain in additionalEndpointSubdomains: if (deployValidatedPrivateDns && length(apimPrivateIpAddresses) > 0) {
  parent: privateDnsZone
  name: '${apimGatewayRecordName}.${subdomain}'
  properties: {
    ttl: 300
    aRecords: [for ip in apimPrivateIpAddresses: {
      ipv4Address: ip
    }]
  }
}]

var normalizedExternalDnsValidationReference = toLower(trim(externalDnsValidationReference))
var externalDnsValidationReferenceIsPlaceholder = contains(externalDnsValidationReference, '<') || contains(externalDnsValidationReference, '>') || contains(normalizedExternalDnsValidationReference, 'placeholder') || contains(normalizedExternalDnsValidationReference, 'replace-me') || normalizedExternalDnsValidationReference == 'todo' || normalizedExternalDnsValidationReference == 'tbd'
var externalDnsValidated = endpointMode == 'custom'
  ? (empty(normalizedExternalDnsValidationReference)
      ? customEndpointsReady
      : fail('Custom readiness uses endpointValidationEvidence, not externalDnsValidationReference.'))
  : empty(normalizedExternalDnsValidationReference)
  ? false
  : (!externalDnsValidationReferenceIsPlaceholder
      ? (!deployPrivateDns
          ? true
          : fail('externalDnsValidationReference applies only when deployPrivateDns is false.'))
      : fail('externalDnsValidationReference must contain real, non-placeholder external DNS validation evidence.'))

output privateDnsZoneId string = deployPrivateDns ? privateDnsZone.id : ''
output privateDnsLinkId string = deployPrivateDns ? privateDnsVnetLink.id : ''
output apimGatewayFqdn string = endpointConfigurationValidated
  ? (endpointMode == 'custom' ? customEndpointHostnames.gateway : '${apimGatewayRecordName}.${privateDnsZoneName}')
  : ''
output apimGatewayRecordId string = deployPrivateDns && length(apimPrivateIpAddresses) > 0 ? apimGatewayRecord.id : ''
output additionalEndpointFqdns array = endpointMode == 'custom'
  ? [customEndpointHostnames.developerPortal, customEndpointHostnames.management]
  : map(additionalEndpointSubdomains, subdomain => '${apimGatewayRecordName}.${subdomain}.${privateDnsZoneName}')
output dnsReadiness object = {
  mode: deployPrivateDns ? 'blueprint' : 'external'
  zone: deployPrivateDns ? 'deployed' : 'external'
  link: deployPrivateDns ? 'deployed' : 'external'
  record: !deployPrivateDns ? (externalDnsValidated ? 'validated' : 'external-handoff-required') : (length(apimPrivateIpAddresses) > 0 ? 'deployed' : 'pending')
  additionalEndpointRecords: !deployPrivateDns ? (externalDnsValidated ? 'validated' : 'external-handoff-required') : (length(apimPrivateIpAddresses) > 0 ? 'deployed' : 'pending')
  privateIpCount: length(apimPrivateIpAddresses)
  externalDnsValidation: externalDnsValidated ? 'validated' : (!deployPrivateDns ? 'required' : 'not-required')
  externalDnsValidationReference: externalDnsValidated
    ? (endpointMode == 'custom' ? endpointValidationEvidence.validationReference : externalDnsValidationReference)
    : ''
  endpointValidationStatus: endpointMode == 'custom' ? (endpointValidationEvidence.?status ?? 'blocked') : 'not-required'
  status: (deployPrivateDns && length(apimPrivateIpAddresses) > 0) || (externalDnsValidated && length(apimPrivateIpAddresses) > 0) ? 'deployed' : 'pending'
}
