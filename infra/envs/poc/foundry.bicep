targetScope = 'resourceGroup'

// Main Foundry deployment: creates the account/project, dependent resources (Storage, AI
// Search, Cosmos DB - new or BYO), bare private endpoints, RBAC assignments, project
// connections, the capability host, and an optional model deployment. Private DNS zone group
// association is intentionally not part of this deployment; run ./foundry-dns.bicep afterward.

param location string = resourceGroup().location

@description('Resource group containing the network foundation (vnet, subnets, private DNS zones). Defaults to this resource group for single-RG deployments.')
param networkResourceGroupName string = resourceGroup().name

param foundryAccountName string = 'foundry-agent-factory-poc'
param projectName string = 'prj-agent-factory-poc'
param projectDisplayName string = 'Agent Factory POC'
param storageAccountName string = 'stagentfactorypoc'
param keyVaultName string = 'kv-agent-factory-poc'
param aiSearchServiceName string = 'srch-agent-factory-poc'
param cosmosDBAccountName string = 'cosmos-agent-factory-poc'
param vnetName string = 'vnet-agent-factory-poc'
param foundrySubnetName string = 'hybridsubnet-foundry'
param privateEndpointSubnetName string = 'hybridsubnet-privateendpoints'

@description('Existing Storage account full ARM resource ID. Leave empty to create a new storage account.')
param existingAzureStorageAccountResourceId string = ''

@description('Set to true if the existing (BYO) storage account already has a private endpoint configured.')
param existingStoragePrivateEndpoint bool = false

@description('Existing AI Search service full ARM resource ID. Leave empty to create a new AI Search service.')
param existingAISearchResourceId string = ''

@description('Set to true if the existing (BYO) AI Search service already has a private endpoint configured.')
param existingAISearchPrivateEndpoint bool = false

@description('Existing Cosmos DB account full ARM resource ID. Leave empty to create a new Cosmos DB account.')
param existingAzureCosmosDBAccountResourceId string = ''

@description('Set to true if the existing (BYO) Cosmos DB account already has a private endpoint configured.')
param existingCosmosDBPrivateEndpoint bool = false

param enableModelDeployment bool = false
param modelDeploymentName string = 'gpt4.1-mini-poc'
param modelName string = 'gpt4.1-mini'
param modelVersion string = '__PENDING_APPROVAL__'
param modelFormat string = 'OpenAI'
param modelSkuName string = 'Standard'
param modelCapacity int = 10

@description('Tags to apply to every taggable resource created by this deployment.')
param tags object = {
  'foundry-poc': 'true'
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  name: vnetName
}

resource foundrySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: foundrySubnetName
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}

module foundry '../../modules/foundry/main.bicep' = {
  name: 'foundry-platform'
  params: {
    location: location
    foundryAccountName: foundryAccountName
    projectName: projectName
    projectDisplayName: projectDisplayName
    foundrySubnetId: foundrySubnet.id
    privateEndpointSubnetId: privateEndpointSubnet.id
    storageAccountName: storageAccountName
    keyVaultName: keyVaultName
    aiSearchServiceName: aiSearchServiceName
    cosmosDBAccountName: cosmosDBAccountName
    existingAzureStorageAccountResourceId: existingAzureStorageAccountResourceId
    existingStoragePrivateEndpoint: existingStoragePrivateEndpoint
    existingAISearchResourceId: existingAISearchResourceId
    existingAISearchPrivateEndpoint: existingAISearchPrivateEndpoint
    existingAzureCosmosDBAccountResourceId: existingAzureCosmosDBAccountResourceId
    existingCosmosDBPrivateEndpoint: existingCosmosDBPrivateEndpoint
    enableModelDeployment: enableModelDeployment
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelVersion: modelVersion
    modelFormat: modelFormat
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    tags: tags
  }
}

output foundryAccountId string = foundry.outputs.foundryAccountId
output foundryProjectId string = foundry.outputs.foundryProjectId
output storageAccountId string = foundry.outputs.storageAccountId
output keyVaultId string = foundry.outputs.keyVaultId
output aiSearchServiceId string = foundry.outputs.aiSearchServiceId
output cosmosDBAccountId string = foundry.outputs.cosmosDBAccountId
output capabilityHostId string = foundry.outputs.capabilityHostId
output foundryPrivateEndpointId string = foundry.outputs.foundryPrivateEndpointId
output storagePrivateEndpointId string = foundry.outputs.storagePrivateEndpointId
output keyVaultPrivateEndpointId string = foundry.outputs.keyVaultPrivateEndpointId
output cosmosDBPrivateEndpointId string = foundry.outputs.cosmosDBPrivateEndpointId
output aiSearchPrivateEndpointId string = foundry.outputs.aiSearchPrivateEndpointId
output foundryPrivateEndpointName string = foundry.outputs.foundryPrivateEndpointName
output storagePrivateEndpointName string = foundry.outputs.storagePrivateEndpointName
output keyVaultPrivateEndpointName string = foundry.outputs.keyVaultPrivateEndpointName
output cosmosDBPrivateEndpointName string = foundry.outputs.cosmosDBPrivateEndpointName
output aiSearchPrivateEndpointName string = foundry.outputs.aiSearchPrivateEndpointName
