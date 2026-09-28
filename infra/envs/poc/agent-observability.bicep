targetScope = 'resourceGroup'

@description('Deployment location.')
param location string = resourceGroup().location

@description('Name of the agent-specific Application Insights component.')
param agentApplicationInsightsName string

@description('Approved existing Log Analytics workspace full ARM resource ID.')
param approvedLogAnalyticsWorkspaceId string

@description('Monitoring-owner approval reference for using the supplied workspace.')
param monitoringOwnerApprovalReference string

@description('Existing APIM-dedicated Application Insights component full ARM resource ID.')
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

module observability '../../modules/agent/observability.bicep' = {
  name: 'phase1-agent-observability'
  params: {
    location: location
    agentApplicationInsightsName: agentApplicationInsightsName
    approvedLogAnalyticsWorkspaceId: approvedLogAnalyticsWorkspaceId
    monitoringOwnerApprovalReference: monitoringOwnerApprovalReference
    apimApplicationInsightsResourceId: apimApplicationInsightsResourceId
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
    tags: tags
  }
}

output agentApplicationInsightsId string = observability.outputs.agentApplicationInsightsId
output agentWorkspaceResourceId string = observability.outputs.agentWorkspaceResourceId
output apimApplicationInsightsId string = observability.outputs.apimApplicationInsightsId
