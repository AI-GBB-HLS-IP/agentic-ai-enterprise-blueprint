using './foundry.bicep'

param location = 'eastus2'
param foundryAccountName = 'foundry-agent-factory-poc'
param projectName = 'prj-agent-factory-poc'
param projectDisplayName = 'Agent Factory POC'
param storageAccountName = 'stagentfactorypoc'
param keyVaultName = 'kv-agent-factory-poc'
param vnetName = 'vnet-agent-factory-poc'
param foundrySubnetName = 'snet-foundry'
param privateEndpointSubnetName = 'snet-privateendpoints'

param enableModelDeployment = true
param modelDeploymentName = 'gpt-4.1-mini'
param modelName = 'gpt-4.1-mini'
param modelVersion = '2025-04-14'
param modelFormat = 'OpenAI'
param modelSkuName = 'Standard'
param modelCapacity = 10
