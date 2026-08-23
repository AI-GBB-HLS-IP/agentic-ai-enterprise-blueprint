targetScope = 'resourceGroup'

@description('Deployment location (defaults to resource group location).')
param location string = resourceGroup().location

@description('APIM gateway service name.')
param apimServiceName string = 'apim-agent-factory-poc'

@description('APIM publisher contact email.')
param publisherEmail string

@description('APIM publisher display name.')
param publisherName string

@description('Existing virtual network name.')
param vnetName string = 'vnet-agent-factory-poc'

@description('Existing APIM subnet name.')
param apimSubnetName string = 'snet-apim'

@description('Existing APIM subnet CIDR.')
param apimSubnetPrefix string = '10.0.1.0/24'

@description('Existing APIM subnet NSG resource name.')
param apimSubnetNsgName string = 'nsg-apim'

@description('Existing Foundry account resource ID.')
param foundryAccountId string

@description('Public network access state. Set Enabled only for initial APIM activation, then disable it.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Existing Foundry account name.')
param foundryAccountName string = 'foundry-agent-factory-poc'

@description('Approved Foundry model deployment name.')
param modelDeploymentName string = 'gpt-4.1-mini'

@description('APIM Premium v2 SKU name.')
@allowed([
  'PremiumV2'
])
param apimSkuName string = 'PremiumV2'

@description('APIM Premium v2 capacity.')
@minValue(1)
param apimSkuCapacity int = 1

@description('APIM backend resource name.')
param backendName string = 'foundry-openai-backend'

@description('Client-facing API resource name.')
param apiName string = 'enterprise-llm-api'

@description('Client-facing API display name.')
param apiDisplayName string = 'Enterprise LLM API'

@description('Client-facing API path prefix.')
param apiPath string = 'llm/v1'

@description('Product resource name for subscription enforcement.')
param productName string = 'governed-llm-product'

@description('Product display name.')
param productDisplayName string = 'Governed LLM Product'

@description('Per-subscription token limit per minute.')
@minValue(1)
param tokenLimitPerMinute int = 10000

@description('Foundry OpenAI API version.')
param foundryApiVersion string = '2024-10-21'

@description('Private DNS zone name for internal APIM gateway resolution.')
param privateDnsZoneName string = 'azure-api.net'

@description('A-record name inside azure-api.net for the APIM gateway.')
param privateDnsRecordName string = apimServiceName

@description('Application Insights component name.')
param applicationInsightsName string = 'appi-apim-agent-factory-poc'

@description('Optional existing Log Analytics workspace ID. Leave empty to create one.')
param logAnalyticsWorkspaceId string = ''

@description('Workspace name used when creating a new Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'law-agent-factory-poc'

@description('Azure Monitor diagnostic setting name.')
param diagnosticSettingName string = 'diag-apim-gateway'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: apimSubnetName
}

resource apimSubnetNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' existing = {
  name: apimSubnetNsgName
}

module subnetDelegation '../../modules/apim/subnet-delegation.bicep' = {
  name: 'apim-subnet-delegation'
  params: {
    vnetName: vnetName
    apimSubnetName: apimSubnetName
    apimSubnetPrefix: apimSubnetPrefix
    apimSubnetNsgId: apimSubnetNsg.id
  }
}

module apimMain '../../modules/apim/main.bicep' = {
  name: 'apim-core-gateway'
  params: {
    location: location
    apimServiceName: apimServiceName
    publisherEmail: publisherEmail
    publisherName: publisherName
    apimSubnetId: apimSubnet.id
    subnetDelegationApplied: subnetDelegation.outputs.delegationApplied
    apimSkuName: apimSkuName
    apimSkuCapacity: apimSkuCapacity
    foundryAccountName: foundryAccountName
    foundryAccountId: foundryAccountId
    publicNetworkAccess: publicNetworkAccess
  }
}

module privateDns '../../modules/apim/private-dns.bicep' = {
  name: 'apim-private-dns'
  params: {
    privateDnsZoneName: privateDnsZoneName
    vnetId: vnet.id
    vnetName: vnetName
    apimGatewayRecordName: privateDnsRecordName
    apimPrivateIpAddresses: apimMain.outputs.privateIpAddresses
  }
}

module backend '../../modules/apim/backend.bicep' = {
  name: 'apim-foundry-backend'
  params: {
    apimServiceName: apimServiceName
    backendName: backendName
    foundryAccountName: foundryAccountName
    modelDeploymentName: modelDeploymentName
    foundryApiVersion: foundryApiVersion
  }
}

module api '../../modules/apim/api.bicep' = {
  name: 'apim-governed-chat-api'
  params: {
    apimServiceName: apimServiceName
    apiName: apiName
    apiDisplayName: apiDisplayName
    apiPath: apiPath
    productName: productName
    productDisplayName: productDisplayName
    backendName: backend.outputs.backendName
    foundryServiceUrl: backend.outputs.backendUrl
    backendPolicyXml: backend.outputs.managedIdentityPolicyXml
    tokenLimitPerMinute: tokenLimitPerMinute
    approvedModelName: modelDeploymentName
  }
}

module observability '../../modules/apim/observability.bicep' = {
  name: 'apim-observability'
  params: {
    location: location
    apimServiceName: apimServiceName
    applicationInsightsName: applicationInsightsName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    diagnosticSettingName: diagnosticSettingName
  }
  dependsOn: [
    apimMain
  ]
}

output apimServiceId string = apimMain.outputs.apimServiceId
output apimGatewayHostname string = apimMain.outputs.apimGatewayHostname
output apimPrincipalId string = apimMain.outputs.apimPrincipalId
output apimSubnetId string = apimMain.outputs.subnetId
output apimSubnetDelegationStatus string = apimMain.outputs.subnetDelegationStatus
output apimHasPublicGatewayEndpoint bool = apimMain.outputs.hasPublicGatewayEndpoint
output foundryRoleAssignmentId string = apimMain.outputs.foundryRoleAssignmentId
output privateDnsZoneId string = privateDns.outputs.privateDnsZoneId
output privateDnsLinkId string = privateDns.outputs.privateDnsLinkId
output privateDnsGatewayFqdn string = privateDns.outputs.apimGatewayFqdn
output backendId string = backend.outputs.backendId
output apiId string = api.outputs.apiId
output productId string = api.outputs.productId
output appInsightsId string = observability.outputs.applicationInsightsId
output logAnalyticsWorkspaceId string = observability.outputs.logAnalyticsWorkspaceId
output readiness object = {
  prerequisites: 'existing'
  subnetDelegation: apimMain.outputs.subnetDelegationStatus
  apimGateway: apimMain.outputs.hasPublicGatewayEndpoint ? 'failed' : 'deployed'
  identityRole: 'deployed'
  dns: privateDns.outputs.dnsReadiness.status
  backend: backend.outputs.managedIdentityReadiness.status
  api: api.outputs.tokenPolicies.status
  observability: observability.outputs.observabilityReadiness.status
  mcpA2aComponents: 'absent'
}
