targetScope = 'resourceGroup'

@description('Resource group containing the existing APIM foundation.')
param apimResourceGroupName string = resourceGroup().name

@description('Existing APIM service name.')
param apimServiceName string

@description('Stage 1 apimServiceId output for the validated APIM foundation.')
param stage1ApimServiceId string

@description('Stage 1 foundationReadiness output for the validated APIM foundation.')
param stage1FoundationReadiness object

@description('Resource group containing the existing Foundry account.')
param foundryResourceGroupName string

@description('Existing Foundry account name.')
param foundryAccountName string

@description('Existing Foundry account resource ID.')
param foundryAccountId string

@description('Non-secret customer GenAI Review Board approval reference.')
param genAiApprovalReference string

@description('Non-secret customer Foundry account-enablement reference.')
param foundryEnablementReference string

@description('Maintained customer policy source used for allowed regions and models.')
param customerPolicySource string

@description('Customer-approved Foundry regions from the maintained policy source.')
@minLength(1)
param approvedFoundryRegions array

@description('Approved public model names mapped to Foundry deployment names.')
@minLength(1)
param approvedModels array

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

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  scope: resourceGroup(apimResourceGroupName)
  name: apimServiceName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  scope: resourceGroup(foundryResourceGroupName)
  name: foundryAccountName
}

var foundryIdMatches = toLower(foundryAccount.id) == toLower(foundryAccountId)
  ? true
  : fail('foundryAccountId must identify foundryAccountName in foundryResourceGroupName.')
var apimIdMatchesStage1Handoff = !empty(trim(stage1ApimServiceId)) && toLower(apimService.id) == toLower(trim(stage1ApimServiceId))
  ? true
  : fail('stage1ApimServiceId must match the existing APIM service selected for Stage 2.')
var stage1NetworkReady = (stage1FoundationReadiness.?network ?? '') == 'validated'
var stage1ApimReady = (stage1FoundationReadiness.?apim ?? '') == 'deployed'
var stage1IdentityReady = (stage1FoundationReadiness.?identity ?? '') == 'deployed'
var stage1DnsReady = (stage1FoundationReadiness.?dns ?? '') == 'deployed'
var stage1ObservabilityReady = (stage1FoundationReadiness.?observability ?? '') == 'deployed'
var stage1OverallReady = (stage1FoundationReadiness.?status ?? '') == 'deployed'
var stage1ReadinessValidated = stage1NetworkReady && stage1ApimReady && stage1IdentityReady && stage1DnsReady && stage1ObservabilityReady && stage1OverallReady
  ? true
  : fail('Stage 2 requires the Stage 1 foundationReadiness handoff with network validated and APIM, identity, DNS, observability, and overall status deployed.')
var apimPremiumSkuValidated = toLower(apimService.sku.name) == 'premium'
  ? true
  : fail('Stage 2 requires the existing Stage 1 APIM service to use the Premium SKU.')
var apimInternalNetworkValidated = toLower(apimService.properties.?virtualNetworkType ?? '') == 'internal'
  ? true
  : fail('Stage 2 requires the existing Stage 1 APIM service to use Internal virtual network mode.')
var apimIdentityValidated = !empty(apimService.identity.?principalId ?? '')
  ? true
  : fail('Stage 2 requires the existing Stage 1 APIM service to have a provisioned managed identity.')
var genAiApprovalReferenceValidated = !empty(trim(genAiApprovalReference)) && !contains(genAiApprovalReference, '<') && !contains(genAiApprovalReference, '>')
  ? true
  : fail('genAiApprovalReference must contain non-placeholder customer governance evidence.')
var foundryEnablementReferenceValidated = !empty(trim(foundryEnablementReference)) && !contains(foundryEnablementReference, '<') && !contains(foundryEnablementReference, '>')
  ? true
  : fail('foundryEnablementReference must contain non-placeholder customer governance evidence.')
var customerPolicySourceValidated = !empty(trim(customerPolicySource)) && !contains(customerPolicySource, '<') && !contains(customerPolicySource, '>')
  ? true
  : fail('customerPolicySource must identify a maintained non-placeholder customer policy source.')
var governanceEvidencePresent = genAiApprovalReferenceValidated && foundryEnablementReferenceValidated && customerPolicySourceValidated
var normalizedApprovedRegions = map(approvedFoundryRegions, region => toLower(region))
var foundryRegionApproved = contains(normalizedApprovedRegions, toLower(foundryAccount.location))
  ? true
  : fail('The existing Foundry account is not in a customer-approved region.')
var foundryPrivatePostureApproved = toLower(foundryAccount.properties.?publicNetworkAccess ?? '') == 'disabled'
  ? true
  : fail('The existing Foundry account must disable public network access before integration.')
var enabledApprovedModels = filter(approvedModels, model => model.?enabled ?? false)
var validEnabledApprovedModels = filter(enabledApprovedModels, model => !empty(model.?publicName ?? '') && !empty(model.?deploymentName ?? ''))
var modelAllowlistPresent = length(enabledApprovedModels) > 0 && length(validEnabledApprovedModels) == length(enabledApprovedModels)
  ? true
  : fail('Stage 2 requires at least one enabled approved model mapping with non-empty publicName and deploymentName values.')
var stage1FoundationValidated = apimIdMatchesStage1Handoff && stage1ReadinessValidated && apimPremiumSkuValidated && apimInternalNetworkValidated && apimIdentityValidated
var integrationPrerequisitesValidated = stage1FoundationValidated && foundryIdMatches && governanceEvidencePresent && foundryRegionApproved && foundryPrivatePostureApproved && modelAllowlistPresent

module foundryRoleAssignment '../../modules/apim/foundry-role-assignment.bicep' = {
  name: 'apim-foundry-role-assignment'
  scope: resourceGroup(foundryResourceGroupName)
  params: {
    foundryAccountName: foundryAccountName
    apimPrincipalId: integrationPrerequisitesValidated ? (apimService.identity.?principalId ?? '') : ''
    apimServiceId: apimService.id
  }
}

module backend '../../modules/apim/backend.bicep' = {
  name: 'apim-foundry-backend'
  scope: resourceGroup(apimResourceGroupName)
  params: {
    apimServiceName: apimServiceName
    backendName: backendName
    foundryAccountName: foundryAccountName
    foundryApiVersion: foundryApiVersion
  }
}

module api '../../modules/apim/api.bicep' = {
  name: 'apim-foundry-governed-api'
  scope: resourceGroup(apimResourceGroupName)
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
    approvedModels: integrationPrerequisitesValidated ? validEnabledApprovedModels : []
  }
}

output apimServiceId string = apimService.id
output apimPrincipalId string = apimService.identity.?principalId ?? ''
output foundryAccountId string = foundryAccount.id
output foundryRoleAssignmentId string = foundryRoleAssignment.outputs.foundryRoleAssignmentId
output backendId string = backend.outputs.backendId
output apiId string = api.outputs.apiId
output productId string = api.outputs.productId
output approvedModelsNamedValueId string = api.outputs.approvedModelsNamedValueId
output approvedModels array = validEnabledApprovedModels
output approvedModelCount int = api.outputs.approvedModelCount
output foundationReadiness string = stage1FoundationValidated ? 'validated' : 'failed'
output integrationReadiness object = {
  governance: 'validated'
  stage1Foundation: stage1FoundationValidated ? 'validated' : 'failed'
  apimIdentity: apimIdentityValidated ? 'existing' : 'failed'
  roleAssignment: 'deployed'
  backend: backend.outputs.managedIdentityReadiness.status
  modelMapping: api.outputs.approvedModelCount > 0 ? 'deployed' : 'failed'
  governedApi: api.outputs.tokenPolicies.status
  product: 'deployed'
  status: !empty(apimService.identity.?principalId ?? '') && api.outputs.approvedModelCount > 0 ? 'deployed' : 'failed'
}
