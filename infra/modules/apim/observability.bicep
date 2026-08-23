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

@description('APIM logger name for Application Insights integration.')
param apimLoggerName string = 'application-insights'

@description('APIM diagnostic entity name.')
param apimDiagnosticName string = 'applicationinsights'

@description('Azure Monitor diagnostic setting name.')
param diagnosticSettingName string = 'diag-apim-gateway'

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
    retentionInDays: 30
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

resource apimDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingName
  scope: apimService
  properties: {
    workspaceId: effectiveWorkspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
      {
        category: 'GatewayRequests'
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

output logAnalyticsWorkspaceId string = effectiveWorkspaceId
output applicationInsightsId string = appInsights.id
output apimLoggerId string = apimLogger.id
output apimDiagnosticId string = apimDiagnostic.id
output diagnosticSettingId string = apimDiagnosticSetting.id
output observabilityReadiness object = {
  workspace: empty(logAnalyticsWorkspaceId) ? 'deployed' : 'existing'
  appInsights: 'deployed'
  apimLogger: 'deployed'
  apimDiagnostics: 'deployed'
  diagnosticSetting: 'deployed'
  status: 'deployed'
}
