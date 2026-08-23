targetScope = 'resourceGroup'

@description('Deployment location for the APIM gateway.')
param location string = resourceGroup().location

@description('APIM service name.')
param apimServiceName string

@description('APIM publisher contact email.')
param publisherEmail string

@description('APIM publisher display name.')
param publisherName string

@description('Existing delegated APIM subnet resource ID.')
param apimSubnetId string

@description('Set by composition after the subnet-delegation module runs.')
param subnetDelegationApplied bool

@description('APIM Premium v2 SKU name.')
@allowed([
  'PremiumV2'
])
param apimSkuName string = 'PremiumV2'

@description('APIM SKU capacity units.')
@minValue(1)
param apimSkuCapacity int = 1

@description('Existing Foundry account name.')
param foundryAccountName string

@description('Existing Foundry account resource ID.')
param foundryAccountId string

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
    publicNetworkAccess: 'Disabled'
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
output subnetDelegationStatus string = subnetDelegationApplied ? 'deployed' : 'failed'
output virtualNetworkType string = apimService.properties.virtualNetworkType
output hasPublicGatewayEndpoint bool = hasPublicGatewayEndpoint
output privateIpAddresses array = privateIpAddresses
output foundryRoleAssignmentId string = foundryRoleAssignment.id
output readiness object = {
  prerequisites: 'existing'
  subnetDelegation: subnetDelegationApplied ? 'deployed' : 'failed'
  apimGateway: hasPublicGatewayEndpoint ? 'failed' : 'deployed'
  identityRole: !empty(apimService.identity.principalId) ? 'deployed' : 'pending'
  foundryScope: foundryAccount.id
  foundryScopeInputMatches: foundryScopeInputMatches
  mcpA2aComponents: 'absent'
  status: subnetDelegationApplied && !hasPublicGatewayEndpoint && foundryScopeInputMatches ? 'deployed' : 'failed'
}
