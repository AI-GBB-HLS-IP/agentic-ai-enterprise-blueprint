using './apim-foundry-integration.bicep'

// Stage 2 parameters. Approval and resource values must be supplied from the authorized customer
// environment; placeholders intentionally block live preflight.
param apimResourceGroupName = readEnvironmentVariable('APIM_RESOURCE_GROUP', '')
param apimServiceName = readEnvironmentVariable('APIM_SERVICE_NAME', 'apim-agent-factory-private-poc')
param stage1ApimServiceId = readEnvironmentVariable('APIM_STAGE1_SERVICE_ID', '')
param stage1FoundationReadiness = json(readEnvironmentVariable('APIM_STAGE1_FOUNDATION_READINESS'))

param foundryResourceGroupName = readEnvironmentVariable('FOUNDRY_RESOURCE_GROUP', '')
param foundryAccountName = readEnvironmentVariable('FOUNDRY_ACCOUNT_NAME', '')
param foundryAccountId = readEnvironmentVariable('FOUNDRY_ACCOUNT_ID', '')

param genAiApprovalReference = readEnvironmentVariable('GENAI_APPROVAL_REFERENCE', '')
param foundryEnablementReference = readEnvironmentVariable('FOUNDRY_ENABLEMENT_REFERENCE', '')
param customerPolicySource = readEnvironmentVariable('FOUNDRY_CUSTOMER_POLICY_SOURCE', '')
param approvedFoundryRegions = json(readEnvironmentVariable('FOUNDRY_APPROVED_REGIONS'))

param approvedModels = json(readEnvironmentVariable('FOUNDRY_APPROVED_MODELS', '[]'))

param backendName = readEnvironmentVariable('APIM_FOUNDRY_BACKEND_NAME', 'foundry-openai-backend')
param apiName = readEnvironmentVariable('APIM_GOVERNED_API_NAME', 'enterprise-llm-api')
param apiDisplayName = readEnvironmentVariable('APIM_GOVERNED_API_DISPLAY_NAME', 'Enterprise LLM API')
param apiPath = readEnvironmentVariable('APIM_GOVERNED_API_PATH', 'llm/v1')
param productName = readEnvironmentVariable('APIM_GOVERNED_PRODUCT_NAME', 'governed-llm-product')
param productDisplayName = readEnvironmentVariable('APIM_GOVERNED_PRODUCT_DISPLAY_NAME', 'Governed LLM Product')
param tokenLimitPerMinute = int(readEnvironmentVariable('APIM_TOKEN_LIMIT_PER_MINUTE', '10000'))
param foundryApiVersion = readEnvironmentVariable('FOUNDRY_API_VERSION', '2024-10-21')
