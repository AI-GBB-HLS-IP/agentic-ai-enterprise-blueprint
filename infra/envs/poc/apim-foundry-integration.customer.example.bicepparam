using './apim-foundry-integration.bicep'

// Copy to apim-foundry-integration.customer.bicepparam and replace the placeholders, or export the
// corresponding environment variables. The copy is git-ignored; keep customer identifiers out of
// tracked files.
//
// Stage 2 requires a validated Stage 1 APIM foundation and an existing Foundry account. Variables
// without a default must be exported: APIM_STAGE1_FOUNDATION_READINESS, FOUNDRY_APPROVED_REGIONS.
// Placeholder governance references intentionally fail template validation.
param apimResourceGroupName = readEnvironmentVariable('APIM_RESOURCE_GROUP', '<apim-resource-group>')
param apimServiceName = readEnvironmentVariable('APIM_SERVICE_NAME', '<stage-1-apim-name>')
param stage1ApimServiceId = readEnvironmentVariable('APIM_STAGE1_SERVICE_ID', '<stage-1-apim-resource-id>')
// JSON handoff recorded after Stage 1 validation. Regenerate it after any APIM SKU change.
param stage1FoundationReadiness = json(readEnvironmentVariable('APIM_STAGE1_FOUNDATION_READINESS'))

param foundryResourceGroupName = readEnvironmentVariable('FOUNDRY_RESOURCE_GROUP', '<foundry-resource-group>')
param foundryAccountName = readEnvironmentVariable('FOUNDRY_ACCOUNT_NAME', '<foundry-account-name>')
param foundryAccountId = readEnvironmentVariable('FOUNDRY_ACCOUNT_ID', '<foundry-account-resource-id>')

param genAiApprovalReference = readEnvironmentVariable('GENAI_APPROVAL_REFERENCE', '<customer-genai-approval-reference>')
param foundryEnablementReference = readEnvironmentVariable('FOUNDRY_ENABLEMENT_REFERENCE', '<customer-foundry-enablement-reference>')
param customerPolicySource = readEnvironmentVariable('FOUNDRY_CUSTOMER_POLICY_SOURCE', '<maintained-customer-policy-source>')
// JSON array of approved regions, for example ["eastus2"].
param approvedFoundryRegions = json(readEnvironmentVariable('FOUNDRY_APPROVED_REGIONS'))

// Each enabled entry maps the public model alias callers send to the Foundry deployment name.
// Example: [{"publicName":"gpt-5-mini","deploymentName":"gpt-5-mini","enabled":true}]
param approvedModels = json(readEnvironmentVariable('FOUNDRY_APPROVED_MODELS', '[{"publicName":"<public-model-alias>","deploymentName":"<foundry-deployment-name>","enabled":true}]'))

param backendName = readEnvironmentVariable('APIM_FOUNDRY_BACKEND_NAME', 'foundry-openai-backend')
param apiName = readEnvironmentVariable('APIM_GOVERNED_API_NAME', 'enterprise-llm-api')
param apiDisplayName = readEnvironmentVariable('APIM_GOVERNED_API_DISPLAY_NAME', 'Enterprise LLM API')
param apiPath = readEnvironmentVariable('APIM_GOVERNED_API_PATH', 'llm/v1')
param productName = readEnvironmentVariable('APIM_GOVERNED_PRODUCT_NAME', 'governed-llm-product')
param productDisplayName = readEnvironmentVariable('APIM_GOVERNED_PRODUCT_DISPLAY_NAME', 'Governed LLM Product')
// Reasoning models count reasoning tokens as completion tokens; raise the limit if calls throttle.
param tokenLimitPerMinute = int(readEnvironmentVariable('APIM_TOKEN_LIMIT_PER_MINUTE', '10000'))
param foundryApiVersion = readEnvironmentVariable('FOUNDRY_API_VERSION', '2024-10-21')
