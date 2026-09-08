using './foundry.bicep'

// Example topology: fully-separated (3 RG) — network, Foundry, and APIM each in their own
// resource group. See ../README.md "Deploy" for other supported topologies (1 or 2 RGs); for
// those, adjust or remove networkResourceGroupName below to match the RG you deploy this
// template into.
param location = 'eastus2'
param networkResourceGroupName = 'rg-agent-blueprint-poc-network'
param foundryAccountName = 'foundry-agent-factory-poc'
param projectName = 'prj-agent-factory-poc'
param projectDisplayName = 'Agent Factory POC'
param storageAccountName = 'stagentfactorypoc'
param keyVaultName = 'kv-agent-factory-poc'
param aiSearchServiceName = 'srch-agent-factory-poc'
param cosmosDBAccountName = 'cosmos-agent-factory-poc'
param vnetName = 'vnet-agent-factory-poc'
param foundrySubnetName = 'hybridsubnet-foundry'
param privateEndpointSubnetName = 'hybridsubnet-privateendpoints'

// BYO dependent resources: leave the resource-ID params empty (default) to have this module
// create new Storage / AI Search / Cosmos DB accounts. To reuse existing resources instead
// (e.g. the customer's pre-provisioned dependencies), set the resource ID and, if that
// existing resource already has its own private endpoint, set the matching
// existing*PrivateEndpoint flag to true so this module does not create a duplicate.
param existingAzureStorageAccountResourceId = ''
param existingStoragePrivateEndpoint = false
param existingAISearchResourceId = ''
param existingAISearchPrivateEndpoint = false
param existingAzureCosmosDBAccountResourceId = ''
param existingCosmosDBPrivateEndpoint = false

param enableModelDeployment = true
param modelDeploymentName = 'gpt-4.1-mini'
param modelName = 'gpt-4.1-mini'
param modelVersion = '2025-04-14'
param modelFormat = 'OpenAI'
param modelSkuName = 'Standard'
param modelCapacity = 10
