@description('Deployment location.')
param location string

@description('AI Search service name (new resource only; this module is not invoked when an existing service is reused).')
param aiSearchServiceName string

resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: aiSearchServiceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'standard'
  }
  properties: {
    disableLocalAuth: true
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    hostingMode: 'default'
    partitionCount: 1
    publicNetworkAccess: 'disabled'
    replicaCount: 1
    semanticSearch: 'disabled'
    networkRuleSet: {
      bypass: 'None'
      ipRules: []
    }
  }
}

output aiSearchServiceId string = aiSearch.id
output aiSearchServiceName string = aiSearch.name
