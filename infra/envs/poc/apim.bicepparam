using './apim.bicep'

// Stage 1 foundation parameters. Environment-backed values intentionally fail preflight when
// customer approval evidence or target resource identifiers have not been supplied.
param location = readEnvironmentVariable('APIM_LOCATION', 'eastus')
param apimServiceName = readEnvironmentVariable('APIM_SERVICE_NAME', 'apim-agent-factory-private-poc')
param publisherEmail = readEnvironmentVariable('APIM_PUBLISHER_EMAIL', '')
param publisherName = readEnvironmentVariable('APIM_PUBLISHER_NAME', 'Agent Factory Platform Engineering')

param networkResourceGroupName = readEnvironmentVariable('APIM_NETWORK_RESOURCE_GROUP', '')
param vnetName = readEnvironmentVariable('APIM_VNET_NAME', '')
param apimSubnetName = readEnvironmentVariable('APIM_SUBNET_NAME', '')
param approvedApimNsgResourceId = readEnvironmentVariable('APIM_APPROVED_NSG_RESOURCE_ID', '')
param approvedApimRouteTableResourceId = readEnvironmentVariable('APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID', '')
param subnetNamingExceptionReference = readEnvironmentVariable('APIM_SUBNET_NAMING_EXCEPTION_REFERENCE', '')
param routeTableExceptionReference = readEnvironmentVariable('APIM_ROUTE_TABLE_EXCEPTION_REFERENCE', '')
param requiredServiceEndpoints = json(readEnvironmentVariable('APIM_REQUIRED_SERVICE_ENDPOINTS', '["Microsoft.AzureActiveDirectory","Microsoft.KeyVault","Microsoft.Sql","Microsoft.Storage"]'))

param apimPublicIpAddressName = readEnvironmentVariable('APIM_PUBLIC_IP_NAME', 'pip-apim-agent-factory-poc')
param apimPublicIpDnsLabel = readEnvironmentVariable('APIM_PUBLIC_IP_DNS_LABEL', 'apim-agent-factory-private-poc-mgmt')
param apimPublicIpTags = json(readEnvironmentVariable('APIM_PUBLIC_IP_TAGS', '{"ProjectCode":"APIM"}'))
param publicNetworkAccess = readEnvironmentVariable('APIM_PUBLIC_NETWORK_ACCESS', 'Enabled')
param apimSkuName = readEnvironmentVariable('APIM_SKU_NAME', 'Premium')
param apimSkuCapacity = int(readEnvironmentVariable('APIM_SKU_CAPACITY', '1'))

param privateDnsZoneName = readEnvironmentVariable('APIM_PRIVATE_DNS_ZONE_NAME', 'azure-api.net')
param privateDnsDeploymentMode = readEnvironmentVariable('APIM_PRIVATE_DNS_MODE', 'blueprint')
param privateDnsRecordName = readEnvironmentVariable('APIM_DNS_RECORD_NAME', 'apim-agent-factory-private-poc')

param applicationInsightsName = readEnvironmentVariable('APIM_APP_INSIGHTS_NAME', 'appi-apim-agent-factory-poc')
param logAnalyticsWorkspaceId = readEnvironmentVariable('APIM_LOG_ANALYTICS_WORKSPACE_ID', '')
param logAnalyticsWorkspaceName = readEnvironmentVariable('APIM_LOG_ANALYTICS_WORKSPACE_NAME', 'law-agent-factory-poc')
param diagnosticSettingName = readEnvironmentVariable('APIM_DIAGNOSTIC_SETTING_NAME', 'diag-apim-gateway')
param diagnosticSettingsOwnership = readEnvironmentVariable('APIM_DIAGNOSTIC_SETTINGS_OWNERSHIP', 'policy')
param capacityAlertName = readEnvironmentVariable('APIM_CAPACITY_ALERT_NAME', 'alert-apim-capacity-over-60')
param capacityAlertThreshold = int(readEnvironmentVariable('APIM_CAPACITY_ALERT_THRESHOLD', '60'))
param capacityAlertActionGroupIds = json(readEnvironmentVariable('APIM_CAPACITY_ALERT_ACTION_GROUP_IDS', '[]'))
