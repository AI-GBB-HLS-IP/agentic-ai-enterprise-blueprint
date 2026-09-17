using './apim.bicep'

// Copy to apim.customer.bicepparam and replace customer-specific fallback values or export the
// corresponding environment variables. The file remains safe to keep untracked.
param location = readEnvironmentVariable('APIM_LOCATION', 'eastus')
param apimServiceName = readEnvironmentVariable('APIM_SERVICE_NAME', '<globally-unique-apim-name>')
param publisherEmail = readEnvironmentVariable('APIM_PUBLISHER_EMAIL', '<approved-corporate-email>')
param publisherName = readEnvironmentVariable('APIM_PUBLISHER_NAME', '<approved-publisher-name>')

param networkResourceGroupName = readEnvironmentVariable('APIM_NETWORK_RESOURCE_GROUP', '<network-resource-group>')
param vnetName = readEnvironmentVariable('APIM_VNET_NAME', '<existing-vnet-name>')
param apimSubnetName = readEnvironmentVariable('APIM_SUBNET_NAME', '<existing-apimsubnet-name>')
param approvedApimNsgResourceId = readEnvironmentVariable('APIM_APPROVED_NSG_RESOURCE_ID', '<approved-nsg-resource-id>')
param approvedApimRouteTableResourceId = readEnvironmentVariable('APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID', '<approved-route-table-resource-id>')
param subnetNamingExceptionReference = readEnvironmentVariable('APIM_SUBNET_NAMING_EXCEPTION_REFERENCE', '')
param routeTableExceptionReference = readEnvironmentVariable('APIM_ROUTE_TABLE_EXCEPTION_REFERENCE', '')
param requiredServiceEndpoints = json(readEnvironmentVariable('APIM_REQUIRED_SERVICE_ENDPOINTS', '["Microsoft.AzureActiveDirectory","Microsoft.KeyVault","Microsoft.Sql","Microsoft.Storage"]'))

param apimPublicIpAddressName = readEnvironmentVariable('APIM_PUBLIC_IP_NAME', '<customer-approved-apim-public-ip-name>')
param apimPublicIpDnsLabel = readEnvironmentVariable('APIM_PUBLIC_IP_DNS_LABEL', '<globally-unique-regional-dns-label>')
param apimPublicIpTags = json(readEnvironmentVariable('APIM_PUBLIC_IP_TAGS', '{"ProjectCode":"APIM"}'))
param apimPublicIpDdosProtectionMode = readEnvironmentVariable('APIM_PUBLIC_IP_DDOS_PROTECTION_MODE', 'VirtualNetworkInherited')

param publicNetworkAccess = readEnvironmentVariable('APIM_PUBLIC_NETWORK_ACCESS', 'Enabled')
param apimSkuName = readEnvironmentVariable('APIM_SKU_NAME', 'Developer')
param apimSkuCapacity = int(readEnvironmentVariable('APIM_SKU_CAPACITY', '1'))

param privateDnsZoneName = readEnvironmentVariable('APIM_PRIVATE_DNS_ZONE_NAME', 'azure-api.net')
param privateDnsDeploymentMode = readEnvironmentVariable('APIM_PRIVATE_DNS_MODE', 'external')
param privateDnsRecordName = readEnvironmentVariable('APIM_DNS_RECORD_NAME', '<same-value-as-apimServiceName>')
param externalDnsValidationReference = readEnvironmentVariable('APIM_EXTERNAL_DNS_VALIDATION_REFERENCE', '')

param applicationInsightsName = readEnvironmentVariable('APIM_APP_INSIGHTS_NAME', '<application-insights-name>')
param logAnalyticsWorkspaceId = readEnvironmentVariable('APIM_LOG_ANALYTICS_WORKSPACE_ID', '')
param logAnalyticsWorkspaceName = readEnvironmentVariable('APIM_LOG_ANALYTICS_WORKSPACE_NAME', '<log-analytics-workspace-name>')
param logAnalyticsRetentionInDays = int(readEnvironmentVariable('APIM_LOG_ANALYTICS_RETENTION_DAYS', '90'))
param diagnosticSettingName = readEnvironmentVariable('APIM_DIAGNOSTIC_SETTING_NAME', 'diag-apim-gateway')
param diagnosticSettingsOwnership = readEnvironmentVariable('APIM_DIAGNOSTIC_SETTINGS_OWNERSHIP', 'policy')
param policyOwnedDiagnosticSettingsValidationReference = readEnvironmentVariable('APIM_POLICY_DIAGNOSTICS_VALIDATION_REFERENCE', '')
param capacityAlertName = readEnvironmentVariable('APIM_CAPACITY_ALERT_NAME', 'alert-apim-capacity-over-60')
param capacityAlertThreshold = int(readEnvironmentVariable('APIM_CAPACITY_ALERT_THRESHOLD', '60'))
param capacityAlertActionGroupIds = json(readEnvironmentVariable('APIM_CAPACITY_ALERT_ACTION_GROUP_IDS', '[]'))
