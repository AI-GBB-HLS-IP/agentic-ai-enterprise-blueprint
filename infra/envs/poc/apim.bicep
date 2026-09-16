targetScope = 'resourceGroup'

@description('Deployment location (defaults to resource group location).')
param location string = resourceGroup().location

@description('APIM gateway service name.')
param apimServiceName string = 'apim-agent-factory-private-poc'

@description('APIM publisher corporate email.')
param publisherEmail string

@description('APIM publisher display name.')
param publisherName string

@description('Resource group containing the existing network foundation.')
param networkResourceGroupName string = resourceGroup().name

@description('Existing virtual network name.')
param vnetName string

@description('Existing APIM subnet name.')
param apimSubnetName string

@description('Expected customer-approved NSG resource ID associated with the APIM subnet.')
param approvedApimNsgResourceId string

@description('Expected customer-approved route-table resource ID. Leave empty only with a documented active-policy exception.')
param approvedApimRouteTableResourceId string = ''

@description('Non-secret evidence reference for a tenant-approved APIM subnet naming exception.')
param subnetNamingExceptionReference string = ''

@description('Non-secret evidence reference for an active tenant-approved route-table exception.')
param routeTableExceptionReference string = ''

@description('Required APIM subnet service endpoints.')
param requiredServiceEndpoints array = [
  'Microsoft.AzureActiveDirectory'
  'Microsoft.KeyVault'
  'Microsoft.Sql'
  'Microsoft.Storage'
]

@description('Existing customer-approved Standard static public IP name in the APIM resource group.')
param apimPublicIpAddressName string

@description('APIM public network access policy handoff.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('APIM classic SKU. Developer is permitted for smoke tests; Premium is the production-like default.')
@allowed([
  'Developer'
  'Premium'
])
param apimSkuName string = 'Premium'

@description('APIM SKU capacity. Developer requires exactly one unit.')
@minValue(1)
param apimSkuCapacity int = 1

@description('Private DNS zone name for internal APIM endpoint resolution.')
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

@description('Owner of the APIM resource diagnostic setting.')
@allowed([
  'blueprint'
  'policy'
])
param diagnosticSettingsOwnership string = 'blueprint'

@description('APIM average-capacity alert name.')
param capacityAlertName string = 'alert-apim-capacity-over-60'

@description('APIM average capacity threshold.')
@minValue(60)
@maxValue(100)
param capacityAlertThreshold int = 60

@description('Optional action group resource IDs.')
param capacityAlertActionGroupIds array = []

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  name: vnetName
}

resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: apimSubnetName
}

resource apimPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' existing = {
  name: apimPublicIpAddressName
}

var subnetNameApproved = startsWith(toLower(apimSubnetName), 'apimsubnet-') || !empty(subnetNamingExceptionReference)
  ? true
  : fail('The APIM subnet name must match apimsubnet-* or subnetNamingExceptionReference must identify a tenant-approved exception.')
var subnetNsgId = apimSubnet.properties.networkSecurityGroup.?id ?? ''
var subnetNsgApproved = !empty(approvedApimNsgResourceId) && toLower(subnetNsgId) == toLower(approvedApimNsgResourceId)
  ? true
  : fail('The APIM subnet must use the customer-approved NSG supplied in approvedApimNsgResourceId.')
var subnetRouteTableId = apimSubnet.properties.routeTable.?id ?? ''
var subnetRouteApproved = !empty(approvedApimRouteTableResourceId)
  ? (toLower(subnetRouteTableId) == toLower(approvedApimRouteTableResourceId)
      ? true
      : fail('The APIM subnet route table does not match approvedApimRouteTableResourceId.'))
  : (empty(subnetRouteTableId) && !empty(routeTableExceptionReference)
      ? true
      : fail('Supply the approved APIM route table, or leave the subnet route table empty and provide routeTableExceptionReference.'))
var subnetHasNoDelegation = length(apimSubnet.properties.delegations ?? []) == 0
  ? true
  : fail('Classic Developer and Premium APIM require an undelegated subnet.')
var configuredServiceEndpoints = map(apimSubnet.properties.serviceEndpoints ?? [], endpoint => toLower(endpoint.service))
var normalizedRequiredServiceEndpoints = map(requiredServiceEndpoints, endpoint => toLower(endpoint))
var requiredServiceEndpointsPresent = length(intersection(configuredServiceEndpoints, normalizedRequiredServiceEndpoints)) == length(normalizedRequiredServiceEndpoints)
  ? true
  : fail('The APIM subnet is missing one or more required service endpoints: Microsoft.AzureActiveDirectory, Microsoft.KeyVault, Microsoft.Sql, Microsoft.Storage.')
var networkPolicyValidated = subnetNameApproved && subnetNsgApproved && subnetRouteApproved && subnetHasNoDelegation && requiredServiceEndpointsPresent
var publisherEmailNormalized = toLower(publisherEmail)
var publisherEmailApproved = contains(publisherEmailNormalized, '@') && !endsWith(publisherEmailNormalized, '@example.com') && !endsWith(publisherEmailNormalized, '@contoso.com')
  ? true
  : fail('publisherEmail must be an approved corporate administrator address, not an empty or example-domain value.')
var publicIpApproved = apimPublicIp.sku.name == 'Standard' && apimPublicIp.properties.publicIPAllocationMethod == 'Static' && toLower(apimPublicIp.location) == toLower(location)
  ? true
  : fail('The classic internal APIM public IP must use Standard SKU, Static allocation, and the APIM deployment location.')
var skuCapacityApproved = apimSkuName == 'Developer' && apimSkuCapacity != 1
  ? fail('Developer APIM requires apimSkuCapacity to be 1.')
  : true
var foundationPolicyValidated = networkPolicyValidated && publisherEmailApproved && publicIpApproved && skuCapacityApproved

module apimMain '../../modules/apim/main.bicep' = {
  name: 'apim-foundation-service'
  params: {
    location: location
    apimServiceName: apimServiceName
    publisherEmail: publisherEmail
    publisherName: publisherName
    apimSubnetId: foundationPolicyValidated ? apimSubnet.id : ''
    apimPublicIpAddressId: apimPublicIp.id
    apimSkuName: apimSkuName
    apimSkuCapacity: apimSkuCapacity
    publicNetworkAccess: publicNetworkAccess
  }
}

module privateDns '../../modules/apim/private-dns.bicep' = {
  name: 'apim-foundation-private-dns'
  params: {
    privateDnsZoneName: privateDnsZoneName
    vnetId: vnet.id
    vnetName: vnetName
    apimGatewayRecordName: privateDnsRecordName
    apimPrivateIpAddresses: apimMain.outputs.privateIpAddresses
  }
}

module observability '../../modules/apim/observability.bicep' = {
  name: 'apim-foundation-observability'
  params: {
    location: location
    apimServiceName: apimServiceName
    applicationInsightsName: applicationInsightsName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    diagnosticSettingName: diagnosticSettingName
    diagnosticSettingsOwnership: diagnosticSettingsOwnership
    capacityAlertName: capacityAlertName
    capacityAlertThreshold: capacityAlertThreshold
    capacityAlertActionGroupIds: capacityAlertActionGroupIds
  }
  dependsOn: [
    apimMain
  ]
}

output apimServiceId string = apimMain.outputs.apimServiceId
output apimServiceName string = apimMain.outputs.apimServiceName
output apimGatewayHostname string = apimMain.outputs.apimGatewayHostname
output apimPrincipalId string = apimMain.outputs.apimPrincipalId
output apimSubnetId string = apimMain.outputs.subnetId
output apimVirtualNetworkType string = apimMain.outputs.virtualNetworkType
output apimPublicIpAddressId string = apimMain.outputs.publicIpAddressId
output apimPublicIpPurpose string = apimMain.outputs.publicIpPurpose
output privateIpAddresses array = apimMain.outputs.privateIpAddresses
output privateDnsZoneId string = privateDns.outputs.privateDnsZoneId
output privateDnsLinkId string = privateDns.outputs.privateDnsLinkId
output privateDnsGatewayFqdn string = privateDns.outputs.apimGatewayFqdn
output privateDnsAdditionalEndpointFqdns array = privateDns.outputs.additionalEndpointFqdns
output appInsightsId string = observability.outputs.applicationInsightsId
output logAnalyticsWorkspaceId string = observability.outputs.logAnalyticsWorkspaceId
output diagnosticSettingId string = observability.outputs.diagnosticSettingId
output capacityAlertId string = observability.outputs.capacityAlertId
output foundationReadiness object = {
  network: foundationPolicyValidated ? 'validated' : 'failed'
  apim: apimMain.outputs.readiness.status
  identity: apimMain.outputs.readiness.identity
  dns: privateDns.outputs.dnsReadiness.status
  observability: observability.outputs.observabilityReadiness.status
  status: apimMain.outputs.readiness.status == 'deployed' && privateDns.outputs.dnsReadiness.status == 'deployed' && observability.outputs.observabilityReadiness.status == 'deployed'
    ? 'deployed'
    : 'pending'
}
output integrationReadiness string = 'not-deployed'
