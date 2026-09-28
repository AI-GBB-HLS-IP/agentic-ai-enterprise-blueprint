targetScope = 'resourceGroup'

@description('Resource location for the agent Application Insights component.')
param location string

@description('Name of the agent-specific Application Insights component.')
param agentApplicationInsightsName string

@description('Approved existing Log Analytics workspace full ARM resource ID. This module never creates a workspace.')
param approvedLogAnalyticsWorkspaceId string

@description('Monitoring-owner approval reference for using the supplied workspace.')
param monitoringOwnerApprovalReference string

@description('Existing APIM-dedicated Application Insights component full ARM resource ID; referenced for output only.')
param apimApplicationInsightsResourceId string

@description('Approved Application Insights ingestion access mode.')
@allowed([
  'Disabled'
])
param publicNetworkAccessForIngestion string

@description('Approved Application Insights query access mode.')
@allowed([
  'Disabled'
])
param publicNetworkAccessForQuery string

@description('Tags applied to the agent Application Insights component.')
param tags object = {}

var workspaceParts = split(approvedLogAnalyticsWorkspaceId, '/')
var _validateWorkspaceId = ((length(workspaceParts) == 9) || (length(workspaceParts) == 10 && empty(workspaceParts[9]))) && toLower(workspaceParts[1]) == 'subscriptions' && toLower(workspaceParts[3]) == 'resourcegroups' && toLower(workspaceParts[5]) == 'providers' && toLower(workspaceParts[6]) == 'microsoft.operationalinsights' && toLower(workspaceParts[7]) == 'workspaces' && !empty(workspaceParts[8])
  ? true
  : fail('approvedLogAnalyticsWorkspaceId must be a full ARM resource ID for Microsoft.OperationalInsights/workspaces.')
var _validateMonitoringApproval = !empty(monitoringOwnerApprovalReference)
  ? true
  : fail('monitoringOwnerApprovalReference must identify the approval for the supplied workspace.')
var _validateApimComponentId = !empty(apimApplicationInsightsResourceId)
  ? true
  : fail('apimApplicationInsightsResourceId must identify the existing APIM telemetry component.')
var workspaceSubscriptionId = _validateWorkspaceId ? workspaceParts[2] : ''
var workspaceResourceGroupName = _validateWorkspaceId ? workspaceParts[4] : ''
var validatedAgentApplicationInsightsName = _validateMonitoringApproval && _validateApimComponentId
  ? agentApplicationInsightsName
  : fail('monitoringOwnerApprovalReference and apimApplicationInsightsResourceId are required.')

resource approvedWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  scope: resourceGroup(workspaceSubscriptionId, workspaceResourceGroupName)
  name: workspaceParts[8]
}

resource agentApplicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: validatedAgentApplicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: approvedWorkspace.id
    IngestionMode: 'LogAnalytics'
    DisableIpMasking: false
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
  }
}

output agentApplicationInsightsId string = agentApplicationInsights.id
output agentWorkspaceResourceId string = approvedWorkspace.id
output apimApplicationInsightsId string = _validateApimComponentId ? apimApplicationInsightsResourceId : ''
