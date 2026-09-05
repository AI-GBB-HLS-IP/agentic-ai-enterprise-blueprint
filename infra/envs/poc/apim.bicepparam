using './apim.bicep'

// Example topology: fully-separated (3 RG) — network, Foundry, and APIM each in their own
// resource group. See ../README.md "Deploy" for other supported topologies (1 or 2 RGs); for
// those, adjust or remove networkResourceGroupName/foundryResourceGroupName below to match the
// RG(s) you actually deploy into.
param location = 'eastus2'
param apimServiceName = 'apim-agent-factory-private-poc'
param publisherEmail = 'platform-eng@example.com'
param publisherName = 'Agent Factory Platform Engineering'

param networkResourceGroupName = 'rg-agent-blueprint-poc-network'
param vnetName = 'vnet-agent-factory-poc'
param apimSubnetName = 'hybridsubnet-apim'
param foundryResourceGroupName = 'rg-agent-blueprint-poc-foundry'
param foundryAccountName = 'foundry-agent-factory-poc'
param approvedModels = [
  {
    publicName: 'gpt-4.1-mini'
    deploymentName: 'gpt-4.1-mini'
    enabled: true
  }
]
param publicNetworkAccess = readEnvironmentVariable('APIM_PUBLIC_NETWORK_ACCESS', 'Enabled')

param apimSkuName = 'Premium'
param apimSkuCapacity = 1

param backendName = 'foundry-openai-backend'
param apiName = 'enterprise-llm-api'
param apiDisplayName = 'Enterprise LLM API'
param apiPath = 'llm/v1'
param productName = 'governed-llm-product'
param productDisplayName = 'Governed LLM Product'
param tokenLimitPerMinute = 10000
param foundryApiVersion = '2024-10-21'

param privateDnsZoneName = 'azure-api.net'
param privateDnsRecordName = 'apim-agent-factory-private-poc'

param applicationInsightsName = 'appi-apim-agent-factory-poc'
param logAnalyticsWorkspaceId = ''
param logAnalyticsWorkspaceName = 'law-agent-factory-poc'
param diagnosticSettingName = 'diag-apim-gateway'
