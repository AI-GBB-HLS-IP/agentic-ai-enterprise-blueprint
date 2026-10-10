targetScope = 'resourceGroup'

@description('Deployment location for the APIM gateway.')
param location string = resourceGroup().location

@description('APIM service name.')
param apimServiceName string

@description('APIM publisher contact email.')
param publisherEmail string

@description('APIM publisher display name.')
param publisherName string

@description('Tags applied to the APIM service.')
param apimServiceTags object = {}

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

@description('Custom domain handling. preserve: re-send existingHostnameConfigurations only. merge: existing plus declared (declared wins on the same type/hostName, and on the same type for non-Proxy types). replace: declared only; an empty list removes all custom domains.')
@allowed([
  'preserve'
  'merge'
  'replace'
])
param hostnameMode string = 'preserve'

@description('Custom domains currently on the live APIM service, captured by scripts/apim/get-existing-hostnames.sh. Key Vault-backed certificates only; PFX-backed domains are never returned by APIM and must be declared.')
param existingHostnameConfigurations array = []

@description('Declared custom domains. Each entry: type (Proxy, DeveloperPortal, Management, Scm), hostName, optional defaultSslBinding/negotiateClientCertificate, and either keyVaultId or certificateKey (a key in hostnameCertificates).')
param hostnameConfigurations array = []

@description('PFX certificate material keyed by certificateKey: { <key>: { encodedCertificate: <base64 pfx>, certificatePassword: <password> } }.')
@secure()
param hostnameCertificates object = {}

@description('Public network access state. Classic internal VNet-injected APIM requires Enabled until an approved APIM private-endpoint handoff is implemented.')
@allowed([
  'Enabled'
])
param publicNetworkAccess string = 'Enabled'

var tlsSecurityProperties = {
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'False'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
}

var declaredHostnames = map(hostnameConfigurations, d => union(
  {
    type: d.type
    hostName: d.hostName
    defaultSslBinding: d.?defaultSslBinding ?? false
    negotiateClientCertificate: d.?negotiateClientCertificate ?? false
  },
  contains(d, 'keyVaultId') ? { keyVaultId: d.keyVaultId } : {},
  contains(d, 'certificateKey') ? hostnameCertificates[d.certificateKey] : {}
))
var declaredNames = map(declaredHostnames, d => toLower('${d.type}|${d.hostName}'))
var declaredNonProxyTypes = map(filter(declaredHostnames, d => d.type != 'Proxy'), d => d.type)
var retainedExistingHostnames = filter(existingHostnameConfigurations, e => !contains(declaredNames, toLower('${e.type}|${e.hostName}')) && !contains(declaredNonProxyTypes, e.type))
var effectiveHostnameConfigurations = hostnameMode == 'preserve'
  ? existingHostnameConfigurations
  : hostnameMode == 'merge' ? concat(retainedExistingHostnames, declaredHostnames) : declaredHostnames

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimServiceName
  location: location
  tags: apimServiceTags
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
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    customProperties: tlsSecurityProperties
    hostnameConfigurations: effectiveHostnameConfigurations
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
