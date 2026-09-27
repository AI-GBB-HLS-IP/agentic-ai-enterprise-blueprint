targetScope = 'resourceGroup'

@description('VNet resource ID to link each private DNS zone to.')
param vnetId string

@description('VNet name used to construct consistent link names.')
param vnetName string

@description('Private DNS zone names required for the POC.')
param privateDnsZoneNames object

@description('Purpose-keyed tags for private DNS zones. Accepted keys: cognitiveServices, azureOpenAI, apim, keyVault, storageBlob, sql, cosmosDB, aiSearch.')
param privateDnsZoneTags object = {}

@description('Purpose-keyed tags for private DNS virtual network links. Accepted keys: cognitiveServices, azureOpenAI, apim, keyVault, storageBlob, sql, cosmosDB, aiSearch.')
param privateDnsVnetLinkTags object = {}

var privateDnsKeys = [
  'cognitiveServices'
  'azureOpenAI'
  'apim'
  'keyVault'
  'storageBlob'
  'sql'
  'cosmosDB'
  'aiSearch'
]
var unsupportedZoneTagItems = filter(items(privateDnsZoneTags), item => !contains(privateDnsKeys, item.key))
var unsupportedLinkTagItems = filter(items(privateDnsVnetLinkTags), item => !contains(privateDnsKeys, item.key))
var privateDnsTagsValidated = length(unsupportedZoneTagItems) == 0 && length(unsupportedLinkTagItems) == 0
  ? true
  : length(unsupportedZoneTagItems) > 0
    ? fail('privateDnsZoneTags contains unsupported logical resource key: ${first(unsupportedZoneTagItems).?key ?? ''}')
    : fail('privateDnsVnetLinkTags contains unsupported logical resource key: ${first(unsupportedLinkTagItems).?key ?? ''}')

resource cognitiveServicesZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsTagsValidated ? privateDnsZoneNames.cognitiveServices : ''
  location: 'global'
  tags: privateDnsZoneTags.?cognitiveServices ?? {}
}

resource azureOpenAIZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsTagsValidated ? privateDnsZoneNames.azureOpenAI : ''
  location: 'global'
  tags: privateDnsZoneTags.?azureOpenAI ?? {}
}

resource apimZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsTagsValidated ? privateDnsZoneNames.apim : ''
  location: 'global'
  tags: privateDnsZoneTags.?apim ?? {}
}

resource keyVaultZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsTagsValidated ? privateDnsZoneNames.keyVault : ''
  location: 'global'
  tags: privateDnsZoneTags.?keyVault ?? {}
}

resource storageBlobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsTagsValidated ? privateDnsZoneNames.storageBlob : ''
  location: 'global'
  tags: privateDnsZoneTags.?storageBlob ?? {}
}

resource sqlZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsTagsValidated ? privateDnsZoneNames.sql : ''
  location: 'global'
  tags: privateDnsZoneTags.?sql ?? {}
}

resource cosmosDBZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsTagsValidated && contains(privateDnsZoneNames, 'cosmosDB') ? privateDnsZoneNames.cosmosDB : 'privatelink.documents.azure.com'
  location: 'global'
  tags: privateDnsZoneTags.?cosmosDB ?? {}
}

resource aiSearchZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsTagsValidated && contains(privateDnsZoneNames, 'aiSearch') ? privateDnsZoneNames.aiSearch : 'privatelink.search.windows.net'
  location: 'global'
  tags: privateDnsZoneTags.?aiSearch ?? {}
}

resource cognitiveServicesLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cognitiveServicesZone
  name: privateDnsTagsValidated ? '${vnetName}-link' : ''
  location: 'global'
  tags: privateDnsVnetLinkTags.?cognitiveServices ?? {}
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource azureOpenAILink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: azureOpenAIZone
  name: privateDnsTagsValidated ? '${vnetName}-link' : ''
  location: 'global'
  tags: privateDnsVnetLinkTags.?azureOpenAI ?? {}
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource apimLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: apimZone
  name: privateDnsTagsValidated ? '${vnetName}-link' : ''
  location: 'global'
  tags: privateDnsVnetLinkTags.?apim ?? {}
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource keyVaultLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultZone
  name: privateDnsTagsValidated ? '${vnetName}-link' : ''
  location: 'global'
  tags: privateDnsVnetLinkTags.?keyVault ?? {}
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource storageBlobLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storageBlobZone
  name: privateDnsTagsValidated ? '${vnetName}-link' : ''
  location: 'global'
  tags: privateDnsVnetLinkTags.?storageBlob ?? {}
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource sqlLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: sqlZone
  name: privateDnsTagsValidated ? '${vnetName}-link' : ''
  location: 'global'
  tags: privateDnsVnetLinkTags.?sql ?? {}
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource cosmosDBLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cosmosDBZone
  name: privateDnsTagsValidated ? '${vnetName}-link' : ''
  location: 'global'
  tags: privateDnsVnetLinkTags.?cosmosDB ?? {}
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource aiSearchLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: aiSearchZone
  name: privateDnsTagsValidated ? '${vnetName}-link' : ''
  location: 'global'
  tags: privateDnsVnetLinkTags.?aiSearch ?? {}
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
