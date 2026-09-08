targetScope = 'resourceGroup'

@description('VNet resource ID to link each private DNS zone to.')
param vnetId string

@description('VNet name used to construct consistent link names.')
param vnetName string

@description('Private DNS zone names required for the POC.')
param privateDnsZoneNames object

resource cognitiveServicesZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneNames.cognitiveServices
  location: 'global'
}

resource azureOpenAIZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneNames.azureOpenAI
  location: 'global'
}

resource apimZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneNames.apim
  location: 'global'
}

resource keyVaultZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneNames.keyVault
  location: 'global'
}

resource storageBlobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneNames.storageBlob
  location: 'global'
}

resource sqlZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneNames.sql
  location: 'global'
}

resource cosmosDBZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneNames.cosmosDB
  location: 'global'
}

resource aiSearchZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneNames.aiSearch
  location: 'global'
}

resource cognitiveServicesLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cognitiveServicesZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource azureOpenAILink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: azureOpenAIZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource apimLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: apimZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource keyVaultLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource storageBlobLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storageBlobZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource sqlLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: sqlZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource cosmosDBLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cosmosDBZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource aiSearchLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: aiSearchZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

output zoneIds object = {
  cognitiveServices: cognitiveServicesZone.id
  azureOpenAI: azureOpenAIZone.id
  apim: apimZone.id
  keyVault: keyVaultZone.id
  storageBlob: storageBlobZone.id
  sql: sqlZone.id
  cosmosDB: cosmosDBZone.id
  aiSearch: aiSearchZone.id
}
