targetScope = 'resourceGroup'

@description('Deployment location.')
param location string = resourceGroup().location

@description('Existing APIM service name.')
param apimServiceName string

@description('Application Insights component name.')
param applicationInsightsName string

@description('Optional existing Log Analytics workspace ID. Leave empty to create a workspace.')
param logAnalyticsWorkspaceId string = ''

@description('Workspace name used when a new workspace is created.')
param logAnalyticsWorkspaceName string = 'law-agent-factory-poc'

@description('Log Analytics retention in days.')
@minValue(30)
param logAnalyticsRetentionInDays int = 90

@description('APIM logger name for Application Insights integration.')
param apimLoggerName string = 'application-insights'

@description('APIM diagnostic entity name.')
param apimDiagnosticName string = 'applicationinsights'

@description('Azure Monitor diagnostic setting name.')
param diagnosticSettingName string = 'diag-apim-gateway'

@description('Owner of the APIM resource diagnostic setting. Policy mode avoids deploying a conflicting setting and requires live validation of the policy-created resource.')
@allowed([
  'blueprint'
  'policy'
])
param diagnosticSettingsOwnership string = 'blueprint'

@description('Azure Monitor metric alert name for APIM average capacity.')
param capacityAlertName string = 'alert-apim-capacity-over-60'

@description('Average APIM capacity percentage threshold.')
@minValue(60)
@maxValue(100)
param capacityAlertThreshold int = 60

@description('Optional action group resource IDs notified by the APIM capacity alert.')
param capacityAlertActionGroupIds array = []

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource createdWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (empty(logAnalyticsWorkspaceId)) {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionInDays
    features: {
      searchVersion: 1
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

var effectiveWorkspaceId = empty(logAnalyticsWorkspaceId) ? createdWorkspace.id : logAnalyticsWorkspaceId

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: effectiveWorkspaceId
    IngestionMode: 'LogAnalytics'
    DisableIpMasking: false
  }
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apimService
  name: apimLoggerName
  // The APIM RP stores this child as locationless, but VPCx allowed-region policy evaluates the deployment request.
  #disable-next-line BCP187
  location: location
  properties: {
    loggerType: 'applicationInsights'
    description: 'APIM gateway logger forwarding diagnostic events to Application Insights.'
    resourceId: appInsights.id
    credentials: {
      instrumentationKey: appInsights.properties.InstrumentationKey
    }
    isBuffered: true
  }
}

resource apimDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apimService
  name: apimDiagnosticName
  // The APIM RP stores this child as locationless, but VPCx allowed-region policy evaluates the deployment request.
  #disable-next-line BCP187
  location: location
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    httpCorrelationProtocol: 'W3C'
    logClientIp: false
    operationNameFormat: 'Name'
    verbosity: 'information'
  }
}

resource apimDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (diagnosticSettingsOwnership == 'blueprint') {
  name: diagnosticSettingName
  scope: apimService
  properties: {
    workspaceId: effectiveWorkspaceId
    logs: [
      {
        categoryGroup: 'AllLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource capacityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: capacityAlertName
  location: 'global'
  properties: {
    description: 'APIM average capacity is above the customer threshold.'
    severity: 2
    enabled: true
    scopes: [
      apimService.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'AverageCapacityAboveThreshold'
          metricNamespace: 'Microsoft.ApiManagement/service'
          metricName: 'Capacity'
          operator: 'GreaterThan'
          threshold: capacityAlertThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.ApiManagement/service'
    targetResourceRegion: location
    actions: [for actionGroupId in capacityAlertActionGroupIds: {
      actionGroupId: actionGroupId
    }]
  }
}

output logAnalyticsWorkspaceId string = effectiveWorkspaceId
output applicationInsightsId string = appInsights.id
output apimLoggerId string = apimLogger.id
output apimDiagnosticId string = apimDiagnostic.id
output diagnosticSettingId string = diagnosticSettingsOwnership == 'blueprint' ? apimDiagnosticSetting.id : ''
output diagnosticSettingsOwnership string = diagnosticSettingsOwnership
output capacityAlertId string = capacityAlert.id
output capacityAlertThreshold int = capacityAlertThreshold
output observabilityReadiness object = {
  workspace: empty(logAnalyticsWorkspaceId) ? 'deployed' : 'existing'
  appInsights: 'deployed'
  apimLogger: 'deployed'
  apimDiagnostics: 'deployed'
  diagnosticSetting: diagnosticSettingsOwnership == 'blueprint' ? 'deployed' : 'policy-validation-required'
  diagnosticCategories: [
    'AllLogs'
    'AllMetrics'
  ]
  capacityAlert: 'deployed'
  capacityAlertThreshold: capacityAlertThreshold
  status: diagnosticSettingsOwnership == 'blueprint' ? 'deployed' : 'policy-validation-required'
}
