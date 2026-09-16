using './foundry.bicep'

// Example topology: fully-separated (3 RG) — network, Foundry, and APIM each in their own
// resource group. See ../README.md "Deploy" for other supported topologies (1 or 2 RGs); for
// those, adjust or remove networkResourceGroupName below to match the RG you deploy this
// template into.
//
// This deploys account/project/dependent-resources/private-endpoints only. Private DNS zone
// group association is a separate, subsequent deployment: see foundry-dns.bicepparam.example.
param location = readEnvironmentVariable('FOUNDRY_LOCATION', 'eastus2')
param networkResourceGroupName = readEnvironmentVariable('FOUNDRY_NETWORK_RESOURCE_GROUP', 'rg-agent-blueprint-poc-network')
param foundryAccountName = readEnvironmentVariable('FOUNDRY_ACCOUNT_NAME', 'foundry-agent-factory-poc')
param projectName = readEnvironmentVariable('FOUNDRY_PROJECT_NAME', 'prj-agent-factory-poc')
param projectDisplayName = readEnvironmentVariable('FOUNDRY_PROJECT_DISPLAY_NAME', 'Agent Factory POC')
param storageAccountName = readEnvironmentVariable('FOUNDRY_STORAGE_ACCOUNT_NAME', 'stagentfactorypoc')
param keyVaultName = readEnvironmentVariable('FOUNDRY_KEY_VAULT_NAME', 'kv-agent-factory-poc')
param aiSearchServiceName = readEnvironmentVariable('FOUNDRY_AI_SEARCH_SERVICE_NAME', 'srch-agent-factory-poc')
param cosmosDBAccountName = readEnvironmentVariable('FOUNDRY_COSMOS_DB_ACCOUNT_NAME', 'cosmos-agent-factory-poc')
param vnetName = readEnvironmentVariable('FOUNDRY_VNET_NAME', 'vnet-agent-factory-poc')
param foundrySubnetName = readEnvironmentVariable('FOUNDRY_SUBNET_NAME', 'hybridsubnet-foundry')
param privateEndpointSubnetName = readEnvironmentVariable('FOUNDRY_PRIVATE_ENDPOINT_SUBNET_NAME', 'hybridsubnet-privateendpoints')

// BYO dependent resources: leave the resource-ID params empty (default) to have this module
// create new Storage / AI Search / Cosmos DB accounts. To reuse existing resources instead
// (e.g. the customer's pre-provisioned dependencies), set the resource ID and, if that
// existing resource already has its own private endpoint, set the matching
// existing*PrivateEndpoint flag to true so this module does not create a duplicate.
param existingAzureStorageAccountResourceId = readEnvironmentVariable('FOUNDRY_EXISTING_STORAGE_ACCOUNT_ID', '')
param existingStoragePrivateEndpoint = bool(readEnvironmentVariable('FOUNDRY_EXISTING_STORAGE_PRIVATE_ENDPOINT', 'false'))
param existingAISearchResourceId = readEnvironmentVariable('FOUNDRY_EXISTING_AI_SEARCH_ID', '')
param existingAISearchPrivateEndpoint = bool(readEnvironmentVariable('FOUNDRY_EXISTING_AI_SEARCH_PRIVATE_ENDPOINT', 'false'))
param existingAzureCosmosDBAccountResourceId = readEnvironmentVariable('FOUNDRY_EXISTING_COSMOS_DB_ACCOUNT_ID', '')
param existingCosmosDBPrivateEndpoint = bool(readEnvironmentVariable('FOUNDRY_EXISTING_COSMOS_DB_PRIVATE_ENDPOINT', 'false'))

param enableModelDeployment = bool(readEnvironmentVariable('FOUNDRY_ENABLE_MODEL_DEPLOYMENT', 'true'))
param modelDeploymentName = readEnvironmentVariable('FOUNDRY_MODEL_DEPLOYMENT_NAME', 'gpt-4.1-mini')
param modelName = readEnvironmentVariable('FOUNDRY_MODEL_NAME', 'gpt-4.1-mini')
param modelVersion = readEnvironmentVariable('FOUNDRY_MODEL_VERSION', '2025-04-14')
param modelFormat = readEnvironmentVariable('FOUNDRY_MODEL_FORMAT', 'OpenAI')
param modelSkuName = readEnvironmentVariable('FOUNDRY_MODEL_SKU_NAME', 'Standard')
param modelCapacity = int(readEnvironmentVariable('FOUNDRY_MODEL_CAPACITY', '10'))
