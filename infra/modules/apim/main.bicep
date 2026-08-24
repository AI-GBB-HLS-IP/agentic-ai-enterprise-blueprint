targetScope = 'resourceGroup'

@description('Deployment location for the APIM gateway.')
param location string = resourceGroup().location

@description('APIM service name.')
param apimServiceName string

@description('APIM publisher contact email.')
param publisherEmail string

@description('APIM publisher display name.')
param publisherName string

@description('Existing APIM subnet resource ID for classic Premium VNet injection.')
param apimSubnetId string

@description('APIM classic Premium SKU name. Premium v2 remains the preferred future tier.')
@allowed([
  'Premium'
])
param apimSkuName string = 'Premium'

@description('APIM SKU capacity units.')
@minValue(1)
param apimSkuCapacity int = 1

@description('Existing Foundry account name.')
param foundryAccountName string

@description('Existing Foundry account resource ID.')
param foundryAccountId string

@description('Public network access state. APIM requires Enabled during initial activation and can be disabled after provisioning.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
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
    publicNetworkAccess: publicNetworkAccess
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
  }
}

var cognitiveServicesOpenAiUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
)

resource foundryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(apimService.id, foundryAccount.id, cognitiveServicesOpenAiUserRoleDefinitionId)
  scope: foundryAccount
  properties: {
    principalId: apimService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cognitiveServicesOpenAiUserRoleDefinitionId
  }
}

var publicIpAddresses = !empty(apimService.properties.publicIPAddresses) ? apimService.properties.publicIPAddresses : []
var privateIpAddresses = !empty(apimService.properties.privateIPAddresses) ? apimService.properties.privateIPAddresses : []
var hasPublicGatewayEndpoint = length(publicIpAddresses) > 0
var gatewayHostname = '${apimServiceName}.azure-api.net'
var foundryScopeInputMatches = toLower(foundryAccountId) == toLower(foundryAccount.id)

output apimServiceId string = apimService.id
output apimGatewayHostname string = gatewayHostname
output apimPrincipalId string = apimService.identity.principalId
output subnetId string = apimSubnetId
output subnetDelegationStatus string = 'not-required'
output virtualNetworkType string = apimService.properties.virtualNetworkType
output hasPublicGatewayEndpoint bool = hasPublicGatewayEndpoint
output privateIpAddresses array = privateIpAddresses
output foundryRoleAssignmentId string = foundryRoleAssignment.id
output readiness object = {
  prerequisites: 'existing'
  subnetDelegation: 'not-required'
  apimGateway: hasPublicGatewayEndpoint ? 'failed' : 'deployed'
  identityRole: !empty(apimService.identity.principalId) ? 'deployed' : 'pending'
  foundryScope: foundryAccount.id
  foundryScopeInputMatches: foundryScopeInputMatches
  mcpA2aComponents: 'absent'
  status: !hasPublicGatewayEndpoint && foundryScopeInputMatches ? 'deployed' : 'failed'
}
