using './apim-foundry-integration.bicep'

// Stage 2 parameters. Approval and resource values must be supplied from the authorized customer
// environment; placeholders intentionally block live preflight.
param apimResourceGroupName = readEnvironmentVariable('APIM_RESOURCE_GROUP', '')
param apimServiceName = readEnvironmentVariable('APIM_SERVICE_NAME', 'apim-agent-factory-private-poc')

param foundryResourceGroupName = readEnvironmentVariable('FOUNDRY_RESOURCE_GROUP', '')
param foundryAccountName = readEnvironmentVariable('FOUNDRY_ACCOUNT_NAME', '')
param foundryAccountId = readEnvironmentVariable('FOUNDRY_ACCOUNT_ID', '')

param genAiApprovalReference = readEnvironmentVariable('GENAI_APPROVAL_REFERENCE', '')
param foundryEnablementReference = readEnvironmentVariable('FOUNDRY_ENABLEMENT_REFERENCE', '')
param customerPolicySource = readEnvironmentVariable('FOUNDRY_CUSTOMER_POLICY_SOURCE', '')
param approvedFoundryRegions = [
  'eastus'
  'eastus2'
  'westeurope'
]
param requirePrivateFoundryAccess = true

param approvedModels = [
  {
    publicName: readEnvironmentVariable('FOUNDRY_PUBLIC_MODEL_NAME', '')
    deploymentName: readEnvironmentVariable('FOUNDRY_MODEL_DEPLOYMENT_NAME', '')
    enabled: true
  }
]

param backendName = 'foundry-openai-backend'
param apiName = 'enterprise-llm-api'
param apiDisplayName = 'Enterprise LLM API'
param apiPath = 'llm/v1'
param productName = 'governed-llm-product'
param productDisplayName = 'Governed LLM Product'
param tokenLimitPerMinute = 10000
param foundryApiVersion = '2024-10-21'
