@description('Deployment location.')
param location string

@description('Cosmos DB account name (new resource only; this module is not invoked when an existing account is reused).')
param cosmosDBAccountName string

@description('Tags to apply to this resource.')
param tags object = {}

resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: cosmosDBAccountName
  location: location
  kind: 'GlobalDocumentDB'
  tags: tags
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    disableLocalAuth: true
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: 'Disabled'
    enableFreeTier: false
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 720
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

output cosmosDBAccountId string = cosmosDB.id
output cosmosDBAccountName string = cosmosDB.name
output cosmosDBDocumentEndpoint string = cosmosDB.properties.documentEndpoint
