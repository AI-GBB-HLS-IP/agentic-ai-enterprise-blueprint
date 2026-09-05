targetScope = 'resourceGroup'

@description('Existing Foundry account name. This file is deployed with scope: resourceGroup(foundryResourceGroupName) so the account is looked up in its own resource group.')
param foundryAccountName string

@description('APIM managed identity principal ID to grant Cognitive Services OpenAI User on the Foundry account.')
param apimPrincipalId string

@description('APIM service resource ID, used only to make the role assignment GUID deterministic and unique per APIM instance.')
param apimServiceId string

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

var cognitiveServicesOpenAiUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
)

resource foundryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(apimServiceId, foundryAccount.id, cognitiveServicesOpenAiUserRoleDefinitionId)
  scope: foundryAccount
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cognitiveServicesOpenAiUserRoleDefinitionId
  }
}

output foundryRoleAssignmentId string = foundryRoleAssignment.id
output foundryAccountResourceId string = foundryAccount.id
