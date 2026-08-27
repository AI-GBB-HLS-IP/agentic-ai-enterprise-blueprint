targetScope = 'resourceGroup'

@description('Existing APIM service name.')
param apimServiceName string

@description('Client-facing API name.')
param apiName string = 'enterprise-llm-api'

@description('Client-facing API display name.')
param apiDisplayName string = 'Enterprise LLM API'

@description('Client-facing API path prefix.')
param apiPath string = 'llm/v1'

@description('Product name enforcing APIM subscriptions.')
param productName string = 'governed-llm-product'

@description('Product display name.')
param productDisplayName string = 'Governed LLM Product'

@description('Backend name already created in APIM.')
param backendName string = 'foundry-openai-backend'

@description('Foundry endpoint base URL used as API serviceUrl.')
param foundryServiceUrl string

@description('Raw APIM policy statements for backend routing/authentication.')
param backendPolicyXml string

@description('Token limit applied per subscription per minute.')
@minValue(1)
param tokenLimitPerMinute int = 10000

@description('Approved public model names mapped to Foundry deployment names.')
@minLength(1)
param approvedModels array

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource approvedModelsNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apimService
  name: 'approved-models'
  properties: {
    displayName: 'approved-models'
    value: base64(string(approvedModels))
    secret: false
    tags: [
      'model-governance'
    ]
  }
}

resource governedProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apimService
  name: productName
  properties: {
    displayName: productDisplayName
    description: 'Subscription-key-protected product exposing only the approved chat/completions API.'
    subscriptionRequired: true
    approvalRequired: false
    subscriptionsLimit: 1
    state: 'published'
  }
}

resource chatApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apimService
  name: apiName
  properties: {
    displayName: apiDisplayName
    path: apiPath
    protocols: [
      'https'
    ]
    serviceUrl: foundryServiceUrl
    subscriptionRequired: true
  }
}

resource chatOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: chatApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    method: 'POST'
    urlTemplate: '/chat/completions'
    request: {
      queryParameters: [
        {
          name: 'api-version'
          required: false
          type: 'string'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Successful model response.'
      }
    ]
  }
}

resource productApiBinding 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: governedProduct
  name: apiName
}

var apiPolicyXml = concat(
  '<policies>\n',
  '  <inbound>\n',
  '    <base />\n',
  '    <check-header name="Ocp-Apim-Subscription-Key" failed-check-httpcode="401" failed-check-error-message="A valid subscription key is required." ignore-case="true" />\n',
  '    <set-variable name="requestedModel" value="@{\n',
  '      try {\n',
  '        var requestBody = context.Request.Body.As<JObject>(preserveContent: true);\n',
  '        return requestBody == null ? null : (string)requestBody[&quot;model&quot;];\n',
  '      } catch {\n',
  '        return null;\n',
  '      }\n',
  '    }" />\n',
  '    <set-variable name="resolvedDeploymentName" value="@{\n',
  '      var requestedModel = (string)context.Variables[&quot;requestedModel&quot;];\n',
  '      if (string.IsNullOrEmpty(requestedModel)) {\n',
  '        return null;\n',
  '      }\n',
  '      try {\n',
  '        var encodedModels = &quot;{{approved-models}}&quot;;\n',
  '        if (string.IsNullOrEmpty(encodedModels)) {\n',
  '          return null;\n',
  '        }\n',
  '        var modelsJson = System.Text.Encoding.UTF8.GetString(System.Convert.FromBase64String(encodedModels));\n',
  '        var models = Newtonsoft.Json.Linq.JArray.Parse(modelsJson);\n',
  '        foreach (var token in models) {\n',
  '          var model = token as Newtonsoft.Json.Linq.JObject;\n',
  '          if (model == null) {\n',
  '            continue;\n',
  '          }\n',
  '          var enabledToken = model[&quot;enabled&quot;];\n',
  '          var isEnabled = enabledToken != null &amp;&amp; enabledToken.Type == Newtonsoft.Json.Linq.JTokenType.Boolean &amp;&amp; (bool)enabledToken;\n',
  '          if (!isEnabled) {\n',
  '            continue;\n',
  '          }\n',
  '          if (string.Equals((string)model[&quot;publicName&quot;], requestedModel, System.StringComparison.Ordinal)) {\n',
  '            return (string)model[&quot;deploymentName&quot;];\n',
  '          }\n',
  '        }\n',
  '      } catch {\n',
  '      }\n',
  '      return null;\n',
  '    }" />\n',
  '    <choose>\n',
  '      <when condition="@(context.Variables[&quot;resolvedDeploymentName&quot;] == null)">\n',
  '        <return-response>\n',
  '          <set-status code="400" reason="Bad Request" />\n',
  '          <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>\n',
  '          <set-body>{&quot;error&quot;:{&quot;code&quot;:&quot;unsupported_model&quot;,&quot;message&quot;:&quot;The requested model is not approved.&quot;}}</set-body>\n',
  '        </return-response>\n',
  '      </when>\n',
  '    </choose>\n',
  '    <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="', string(tokenLimitPerMinute), '" estimate-prompt-tokens="true" remaining-tokens-variable-name="remainingTokens" />\n',
  '    <llm-emit-token-metric namespace="ai-gateway-metrics">\n',
  '      <dimension name="Subscription" value="@(context.Subscription.Id)" />\n',
  '      <dimension name="API" value="@(context.Api.Id)" />\n',
  '    </llm-emit-token-metric>\n',
  '    ', backendPolicyXml, '\n',
  '  </inbound>\n',
  '  <backend>\n',
  '    <base />\n',
  '  </backend>\n',
  '  <outbound>\n',
  '    <base />\n',
  '  </outbound>\n',
  '  <on-error>\n',
  '    <base />\n',
  '  </on-error>\n',
  '</policies>'
)

resource chatApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: chatApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: apiPolicyXml
  }
  dependsOn: [
    approvedModelsNamedValue
  ]
}

output apiId string = chatApi.id
output operationId string = chatOperation.id
output apiPolicyId string = chatApiPolicy.id
output productId string = governedProduct.id
output approvedModelsNamedValueId string = approvedModelsNamedValue.id
output approvedModelCount int = length(approvedModels)
output backendBinding string = backendName
output tokenPolicies object = {
  tokenLimitPolicy: 'llm-token-limit'
  tokenMetricPolicy: 'llm-emit-token-metric'
  status: 'deployed'
}
output scopeBoundary object = {
  declaredApis: [
    '${apiPath}/chat/completions'
  ]
  mcpApiCreated: false
  a2aApiCreated: false
}
