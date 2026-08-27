targetScope = 'resourceGroup'

@description('Existing APIM service name.')
param apimServiceName string

@description('Backend resource name in APIM.')
param backendName string = 'foundry-openai-backend'

@description('Existing Foundry account name used to construct the OpenAI endpoint.')
param foundryAccountName string

@description('Foundry OpenAI API version.')
param foundryApiVersion string = '2024-10-21'

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

var foundryBaseUrl = 'https://${foundryAccountName}.openai.azure.com'

resource foundryBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apimService
  name: backendName
  properties: {
    title: 'Foundry approved-model backend'
    description: 'Managed-identity backend for approved Foundry model deployments.'
    protocol: 'http'
    url: foundryBaseUrl
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

var managedIdentityPolicyXml = concat(
  '<set-backend-service backend-id="', backendName, '" />\n',
  '<rewrite-uri template="@(&quot;/openai/deployments/&quot; + (string)context.Variables[&quot;resolvedDeploymentName&quot;] + &quot;/chat/completions&quot;)" />\n',
  '<set-query-parameter name="api-version" exists-action="override">\n',
  '  <value>', foundryApiVersion, '</value>\n',
  '</set-query-parameter>\n',
  '<authentication-managed-identity resource="https://cognitiveservices.azure.com" ignore-error="false" />'
)

output backendId string = foundryBackend.id
output backendName string = foundryBackend.name
output backendUrl string = foundryBaseUrl
output managedIdentityPolicyXml string = managedIdentityPolicyXml
output managedIdentityReadiness object = {
  backend: 'deployed'
  authMode: 'authentication-managed-identity'
  routingMode: 'approved-model-configuration'
  status: 'deployed'
}
