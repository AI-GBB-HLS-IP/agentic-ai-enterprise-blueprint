targetScope = 'resourceGroup'

@description('Deployment location for the APIM gateway.')
param location string = resourceGroup().location

@description('APIM service name.')
param apimServiceName string

@description('APIM publisher contact email.')
param publisherEmail string

@description('APIM publisher display name.')
param publisherName string

@description('Existing APIM subnet resource ID for classic Developer or Premium VNet injection.')
param apimSubnetId string

@description('Existing customer-approved Standard static public IP resource ID used by classic internal APIM for platform management.')
param apimPublicIpAddressId string

@description('APIM classic SKU name. Developer is for smoke tests only; Premium remains the production-like default.')
@allowed([
  'Developer'
  'Premium'
])
param apimSkuName string = 'Premium'

@description('APIM SKU capacity units.')
@minValue(1)
param apimSkuCapacity int = 1

@description('Public network access state. Internal VNet injection keeps service endpoints private; disabling this flag requires an approved APIM private endpoint.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

var tlsSecurityProperties = {
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
}

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimServiceName
  location: location
  sku: {
    name: apimSkuName
    capacity: apimSkuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicIpAddressId: apimPublicIpAddressId
    publicNetworkAccess: publicNetworkAccess
    legacyPortalStatus: 'Disabled'
    natGatewayState: 'Disabled'
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    customProperties: tlsSecurityProperties
  }
}

var privateIpAddresses = !empty(apimService.properties.privateIPAddresses)
  ? apimService.properties.privateIPAddresses
  : []

output apimServiceId string = apimService.id
output apimServiceName string = apimService.name
output apimGatewayHostname string = '${apimServiceName}.azure-api.net'
output apimPrincipalId string = apimService.identity.principalId
output subnetId string = apimSubnetId
output virtualNetworkType string = apimService.properties.virtualNetworkType
output publicIpAddressId string = apimPublicIpAddressId
output publicIpPurpose string = 'classic-internal-platform-management'
output privateIpAddresses array = privateIpAddresses
output securityBaseline object = {
  sku: apimSkuName
  internalVnet: apimService.properties.virtualNetworkType == 'Internal'
  systemAssignedIdentity: !empty(apimService.identity.principalId)
  minimumTlsVersion: '1.2'
  httpsBackendsRequired: true
  weakProtocolsAndCiphersDisabled: true
}
output readiness object = {
  apim: 'deployed'
  identity: !empty(apimService.identity.principalId) ? 'deployed' : 'pending'
  networkMode: apimService.properties.virtualNetworkType
  publicIpPurpose: 'classic-internal-platform-management'
  status: !empty(apimService.identity.principalId) ? 'deployed' : 'pending'
}
