using './apim.bicep'

param location = 'eastus2'
param apimServiceName = 'apim-agent-factory-poc'
param publisherEmail = 'platform-eng@example.com'
param publisherName = 'Agent Factory Platform Engineering'

param vnetName = 'vnet-agent-factory-poc'
param apimSubnetName = 'snet-apim'
param apimSubnetPrefix = '10.0.1.0/24'
param apimSubnetNsgName = 'nsg-apim'

param foundryAccountId = resourceId('Microsoft.CognitiveServices/accounts', 'foundry-agent-factory-poc')
param foundryAccountName = 'foundry-agent-factory-poc'
param modelDeploymentName = 'gpt-4.1-mini'

param apimSkuName = 'PremiumV2'
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
param privateDnsRecordName = 'apim-agent-factory-poc'

param applicationInsightsName = 'appi-apim-agent-factory-poc'
param logAnalyticsWorkspaceId = ''
param logAnalyticsWorkspaceName = 'law-agent-factory-poc'
param diagnosticSettingName = 'diag-apim-gateway'
