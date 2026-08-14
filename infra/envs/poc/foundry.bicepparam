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

// Keep false until AI CoE approval records the exact model version and capacity.
param enableModelDeployment = false
param modelDeploymentName = 'gpt4.1-mini-poc'
param modelName = 'gpt4.1-mini'
param modelVersion = '__PENDING_APPROVAL__'
param modelFormat = 'OpenAI'
param modelSkuName = 'Standard'
param modelCapacity = 10
