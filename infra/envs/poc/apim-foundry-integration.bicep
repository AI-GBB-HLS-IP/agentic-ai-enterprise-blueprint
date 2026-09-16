targetScope = 'resourceGroup'

@description('Resource group containing the existing APIM foundation.')
param apimResourceGroupName string = resourceGroup().name

@description('Existing APIM service name.')
param apimServiceName string

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

@description('Require the existing Foundry account to disable public network access.')
param requirePrivateFoundryAccess bool = true

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
var governanceEvidencePresent = !empty(genAiApprovalReference) && !empty(foundryEnablementReference) && !empty(customerPolicySource)
  ? true
  : fail('Stage 2 requires GenAI approval, Foundry enablement, and maintained customer policy references.')
var normalizedApprovedRegions = map(approvedFoundryRegions, region => toLower(region))
var foundryRegionApproved = contains(normalizedApprovedRegions, toLower(foundryAccount.location))
  ? true
  : fail('The existing Foundry account is not in a customer-approved region.')
var foundryPrivatePostureApproved = !requirePrivateFoundryAccess || foundryAccount.properties.publicNetworkAccess == 'Disabled'
  ? true
  : fail('The existing Foundry account must disable public network access before integration.')
var enabledApprovedModels = filter(approvedModels, model => model.?enabled ?? false)
var validEnabledApprovedModels = filter(enabledApprovedModels, model => !empty(model.?publicName ?? '') && !empty(model.?deploymentName ?? ''))
var modelAllowlistPresent = length(enabledApprovedModels) > 0 && length(validEnabledApprovedModels) == length(enabledApprovedModels)
  ? true
  : fail('Stage 2 requires at least one enabled approved model mapping with non-empty publicName and deploymentName values.')
var integrationPrerequisitesValidated = foundryIdMatches && governanceEvidencePresent && foundryRegionApproved && foundryPrivatePostureApproved && modelAllowlistPresent

module foundryRoleAssignment '../../modules/apim/foundry-role-assignment.bicep' = {
  name: 'apim-foundry-role-assignment'
  scope: resourceGroup(foundryResourceGroupName)
  params: {
    foundryAccountName: foundryAccountName
    apimPrincipalId: integrationPrerequisitesValidated ? apimService.identity.principalId : ''
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
output apimPrincipalId string = apimService.identity.principalId
output foundryAccountId string = foundryAccount.id
output foundryRoleAssignmentId string = foundryRoleAssignment.outputs.foundryRoleAssignmentId
output backendId string = backend.outputs.backendId
output apiId string = api.outputs.apiId
output productId string = api.outputs.productId
output approvedModelsNamedValueId string = api.outputs.approvedModelsNamedValueId
output approvedModels array = validEnabledApprovedModels
output approvedModelCount int = api.outputs.approvedModelCount
output foundationReadiness string = 'existing-reference'
output integrationReadiness object = {
  governance: 'validated'
  apimIdentity: !empty(apimService.identity.principalId) ? 'existing' : 'failed'
  roleAssignment: 'deployed'
  backend: backend.outputs.managedIdentityReadiness.status
  modelMapping: api.outputs.approvedModelCount > 0 ? 'deployed' : 'failed'
  governedApi: api.outputs.tokenPolicies.status
  product: 'deployed'
  status: !empty(apimService.identity.principalId) && api.outputs.approvedModelCount > 0 ? 'deployed' : 'failed'
}
