targetScope = 'resourceGroup'

@description('Foundry account name.')
param foundryAccountName string

@description('Foundry project name.')
param projectName string

@description('Foundry project display name.')
param projectDisplayName string = projectName

@description('Foundry project description.')
param projectDescription string = 'Private POC Foundry project with BYO VNet networking.'

@description('Deployment location.')
param location string

@description('Existing delegated Foundry subnet resource ID.')
param foundrySubnetId string

@description('Existing private endpoint subnet resource ID.')
param privateEndpointSubnetId string

@description('Existing private DNS zone resource IDs.')
param privateDnsZoneIds object

@description('Storage account name used when creating a new storage account (ignored when existingAzureStorageAccountResourceId is set).')
param storageAccountName string

@description('Key Vault name.')
param keyVaultName string

@description('AI Search service name used when creating a new AI Search service (ignored when existingAISearchResourceId is set).')
param aiSearchServiceName string = '${toLower(foundryAccountName)}search'

@description('Cosmos DB account name used when creating a new Cosmos DB account (ignored when existingAzureCosmosDBAccountResourceId is set).')
param cosmosDBAccountName string = '${toLower(foundryAccountName)}cosmosdb'

@description('Existing Storage account full ARM resource ID. Leave empty to create a new storage account.')
param existingAzureStorageAccountResourceId string = ''

@description('Set to true if the existing (BYO) storage account already has a private endpoint configured; a new one will not be created.')
param existingStoragePrivateEndpoint bool = false

@description('Existing AI Search service full ARM resource ID. Leave empty to create a new AI Search service.')
param existingAISearchResourceId string = ''

@description('Set to true if the existing (BYO) AI Search service already has a private endpoint configured; a new one will not be created.')
param existingAISearchPrivateEndpoint bool = false

@description('Existing Cosmos DB account full ARM resource ID. Leave empty to create a new Cosmos DB account.')
param existingAzureCosmosDBAccountResourceId string = ''

@description('Set to true if the existing (BYO) Cosmos DB account already has a private endpoint configured; a new one will not be created.')
param existingCosmosDBPrivateEndpoint bool = false

@description('Enable the approved model deployment after AI CoE approval.')
param enableModelDeployment bool = false

@description('Approved model deployment name.')
param modelDeploymentName string = 'model-poc'

@description('Approved model name.')
param modelName string = 'gpt4.1-mini'

@description('Approved model version.')
param modelVersion string = '__PENDING_APPROVAL__'

@description('Approved model format.')
param modelFormat string = 'OpenAI'

@description('Approved model serving SKU.')
param modelSkuName string = 'Standard'

@description('Approved model capacity in the SKU quota units.')
param modelCapacity int = 10

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: foundryAccountName
  location: location
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryAccountName
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
      bypass: 'AzureServices'
    }
    publicNetworkAccess: 'Disabled'
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: foundrySubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
    disableLocalAuth: true
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: account
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: projectDescription
    displayName: projectDisplayName
  }
}

var rawWorkspaceId = string(project.properties.internalId)
var _validateWorkspaceId = (length(rawWorkspaceId) == 32) ? true : error('project.properties.internalId must be a 32-character hex GUID; ensure the selected API version returns internalId.')
var projectWorkspaceIdGuid = '${substring(rawWorkspaceId, 0, 8)}-${substring(rawWorkspaceId, 8, 4)}-${substring(rawWorkspaceId, 12, 4)}-${substring(rawWorkspaceId, 16, 4)}-${substring(rawWorkspaceId, 20, 12)}'

module keyVaultResources './supporting-resources.bicep' = {
  name: 'foundry-keyvault'
  params: {
    location: location
    keyVaultName: keyVaultName
  }
}

// --- BYO resolution: Storage, AI Search, Cosmos DB -------------------------------------------
// Each dependency independently supports "create new" (default, empty resource ID) or
// "reference existing" (BYO, non-empty resource ID), and each may live in a different
// subscription/resource group than this Foundry deployment.

var storagePassedIn = !empty(existingAzureStorageAccountResourceId)
var storageParts = split(existingAzureStorageAccountResourceId, '/')
var _validateStorageResourceId = !storagePassedIn || (length(storageParts) == 9 && toLower(storageParts[6]) == 'microsoft.storage' && toLower(storageParts[7]) == 'storageaccounts' && !empty(storageParts[8])) ? true : error('existingAzureStorageAccountResourceId must be a full ARM resource ID for Microsoft.Storage/storageAccounts.')
var storageSubscriptionId = storagePassedIn ? storageParts[2] : subscription().subscriptionId
var storageResourceGroupName = storagePassedIn ? storageParts[4] : resourceGroup().name
var storageAccountNameResolved = storagePassedIn ? storageParts[8] : storageAccountName

var searchPassedIn = !empty(existingAISearchResourceId)
var searchParts = split(existingAISearchResourceId, '/')
var _validateAISearchResourceId = !searchPassedIn || (length(searchParts) == 9 && toLower(searchParts[6]) == 'microsoft.search' && toLower(searchParts[7]) == 'searchservices' && !empty(searchParts[8])) ? true : error('existingAISearchResourceId must be a full ARM resource ID for Microsoft.Search/searchServices.')
var searchSubscriptionId = searchPassedIn ? searchParts[2] : subscription().subscriptionId
var searchResourceGroupName = searchPassedIn ? searchParts[4] : resourceGroup().name
var aiSearchServiceNameResolved = searchPassedIn ? searchParts[8] : aiSearchServiceName

var cosmosPassedIn = !empty(existingAzureCosmosDBAccountResourceId)
var cosmosParts = split(existingAzureCosmosDBAccountResourceId, '/')
var _validateCosmosDBResourceId = !cosmosPassedIn || (length(cosmosParts) == 9 && toLower(cosmosParts[6]) == 'microsoft.documentdb' && toLower(cosmosParts[7]) == 'databaseaccounts' && !empty(cosmosParts[8])) ? true : error('existingAzureCosmosDBAccountResourceId must be a full ARM resource ID for Microsoft.DocumentDB/databaseAccounts.')
var cosmosSubscriptionId = cosmosPassedIn ? cosmosParts[2] : subscription().subscriptionId
var cosmosResourceGroupName = cosmosPassedIn ? cosmosParts[4] : resourceGroup().name
var cosmosDBAccountNameResolved = cosmosPassedIn ? cosmosParts[8] : cosmosDBAccountName

resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (storagePassedIn) {
  scope: resourceGroup(storageSubscriptionId, storageResourceGroupName)
  name: storageAccountNameResolved
}

module newStorageAccount './storage.bicep' = if (!storagePassedIn) {
  name: 'foundry-storage'
  scope: resourceGroup(storageSubscriptionId, storageResourceGroupName)
  params: {
    location: location
    storageAccountName: storageAccountNameResolved
  }
}

resource existingAISearchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = if (searchPassedIn) {
  scope: resourceGroup(searchSubscriptionId, searchResourceGroupName)
  name: aiSearchServiceNameResolved
}

module newAISearchService './ai-search.bicep' = if (!searchPassedIn) {
  name: 'foundry-ai-search'
  scope: resourceGroup(searchSubscriptionId, searchResourceGroupName)
  params: {
    location: location
    aiSearchServiceName: aiSearchServiceNameResolved
  }
}

resource existingCosmosDBAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = if (cosmosPassedIn) {
  scope: resourceGroup(cosmosSubscriptionId, cosmosResourceGroupName)
  name: cosmosDBAccountNameResolved
}

module newCosmosDBAccount './cosmos-db.bicep' = if (!cosmosPassedIn) {
  name: 'foundry-cosmos-db'
  scope: resourceGroup(cosmosSubscriptionId, cosmosResourceGroupName)
  params: {
    location: location
    cosmosDBAccountName: cosmosDBAccountNameResolved
  }
}

// The conditional resources/modules above are mutually exclusive (storagePassedIn/searchPassedIn/
// cosmosPassedIn partition "existing" vs. "new" for each dependency), so exactly one branch is
// always deployed and safe to read here.
#disable-next-line BCP318
var storageAccountIdResolved = storagePassedIn ? existingStorageAccount.id : newStorageAccount.outputs.storageAccountId
#disable-next-line BCP318
var storageBlobEndpointResolved = storagePassedIn ? existingStorageAccount.properties.primaryEndpoints.blob : 'https://${storageAccountNameResolved}.blob.${environment().suffixes.storage}/'
#disable-next-line BCP318
var storageLocationResolved = storagePassedIn ? existingStorageAccount.location : location

#disable-next-line BCP318
var aiSearchServiceIdResolved = searchPassedIn ? existingAISearchService.id : newAISearchService.outputs.aiSearchServiceId
#disable-next-line BCP318
var aiSearchLocationResolved = searchPassedIn ? existingAISearchService.location : location

#disable-next-line BCP318
var cosmosDBAccountIdResolved = cosmosPassedIn ? existingCosmosDBAccount.id : newCosmosDBAccount.outputs.cosmosDBAccountId
#disable-next-line BCP318
var cosmosDBDocumentEndpointResolved = cosmosPassedIn ? existingCosmosDBAccount.properties.documentEndpoint : newCosmosDBAccount.outputs.cosmosDBDocumentEndpoint
#disable-next-line BCP318
var cosmosDBLocationResolved = cosmosPassedIn ? existingCosmosDBAccount.location : location

module privateEndpoints './private-endpoint.bicep' = {
  name: 'foundry-private-endpoints'
  params: {
    location: location
    privateEndpointSubnetId: privateEndpointSubnetId
    foundryAccountId: account.id
    storageAccountId: storageAccountIdResolved
    keyVaultId: keyVaultResources.outputs.keyVaultId
    cognitiveServicesDnsZoneId: privateDnsZoneIds.cognitiveServices
    openAiDnsZoneId: privateDnsZoneIds.openAi
    servicesAiDnsZoneId: privateDnsZoneIds.servicesAi
    blobDnsZoneId: privateDnsZoneIds.blob
    keyVaultDnsZoneId: privateDnsZoneIds.keyVault
    createStoragePrivateEndpoint: !(storagePassedIn && existingStoragePrivateEndpoint)
    createCosmosDBPrivateEndpoint: !(cosmosPassedIn && existingCosmosDBPrivateEndpoint)
    cosmosDBAccountId: cosmosDBAccountIdResolved
    cosmosDBDnsZoneId: privateDnsZoneIds.cosmosDB
    createAISearchPrivateEndpoint: !(searchPassedIn && existingAISearchPrivateEndpoint)
    aiSearchServiceId: aiSearchServiceIdResolved
    aiSearchDnsZoneId: privateDnsZoneIds.aiSearch
  }
  dependsOn: [
    project
  ]
}

module projectConnections './project-connections.bicep' = {
  name: 'foundry-project-connections'
  params: {
    foundryAccountName: foundryAccountName
    projectName: projectName
    cosmosDBAccountName: cosmosDBAccountNameResolved
    cosmosDBDocumentEndpoint: cosmosDBDocumentEndpointResolved
    cosmosDBAccountId: cosmosDBAccountIdResolved
    cosmosDBLocation: cosmosDBLocationResolved
    storageAccountName: storageAccountNameResolved
    storageBlobEndpoint: storageBlobEndpointResolved
    storageAccountId: storageAccountIdResolved
    storageLocation: storageLocationResolved
    aiSearchServiceName: aiSearchServiceNameResolved
    aiSearchServiceId: aiSearchServiceIdResolved
    aiSearchLocation: aiSearchLocationResolved
  }
  dependsOn: [
    privateEndpoints
  ]
}

module capabilityHost './capability-host.bicep' = {
  name: 'foundry-capability-host'
  params: {
    foundryAccountName: foundryAccountName
    projectName: projectName
    cosmosDBConnectionName: projectConnections.outputs.cosmosDBConnectionName
    storageConnectionName: projectConnections.outputs.storageConnectionName
    aiSearchConnectionName: projectConnections.outputs.aiSearchConnectionName
  }
  dependsOn: [
    cosmosDBRbac
    storageRbac
  ]
}

module cosmosDBRbac './cosmos-rbac.bicep' = {
  name: 'foundry-cosmos-rbac'
  scope: resourceGroup(cosmosSubscriptionId, cosmosResourceGroupName)
  params: {
    projectPrincipalId: project.identity.principalId
    cosmosDBAccountName: cosmosDBAccountNameResolved
    projectWorkspaceIdGuid: projectWorkspaceIdGuid
  }
}

module aiSearchRbac './ai-search-rbac.bicep' = {
  name: 'foundry-ai-search-rbac'
  scope: resourceGroup(searchSubscriptionId, searchResourceGroupName)
  params: {
    projectPrincipalId: project.identity.principalId
    aiSearchServiceName: aiSearchServiceNameResolved
  }
}

module storageRbac './storage-rbac.bicep' = {
  name: 'foundry-storage-rbac'
  scope: resourceGroup(storageSubscriptionId, storageResourceGroupName)
  params: {
    projectPrincipalId: project.identity.principalId
    storageAccountName: storageAccountNameResolved
    projectWorkspaceIdGuid: projectWorkspaceIdGuid
  }
}

module modelDeployment './model-deployment.bicep' = if (enableModelDeployment) {
  name: 'foundry-model-deployment'
  params: {
    foundryAccountName: foundryAccountName
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelVersion: modelVersion
    modelFormat: modelFormat
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
  }
  dependsOn: [
    project
    privateEndpoints
  ]
}

output foundryAccountId string = account.id
output foundryProjectId string = project.id
output foundryAccountPrincipalId string = account.identity.principalId
output foundryProjectPrincipalId string = project.identity.principalId
output storageAccountId string = storageAccountIdResolved
output keyVaultId string = keyVaultResources.outputs.keyVaultId
output aiSearchServiceId string = aiSearchServiceIdResolved
output cosmosDBAccountId string = cosmosDBAccountIdResolved
output capabilityHostId string = capabilityHost.outputs.capabilityHostId
// The conditional module is guaranteed to exist when this output is read.
#disable-next-line BCP318
output modelDeploymentId string = enableModelDeployment ? modelDeployment.outputs.deploymentId : ''
