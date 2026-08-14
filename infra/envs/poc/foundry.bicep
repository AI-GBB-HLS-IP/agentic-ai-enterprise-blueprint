targetScope = 'resourceGroup'

param location string = resourceGroup().location
param foundryAccountName string = 'foundry-agent-factory-poc'
param projectName string = 'prj-agent-factory-poc'
param projectDisplayName string = 'Agent Factory POC'
param storageAccountName string = 'stagentfactorypoc'
param keyVaultName string = 'kv-agent-factory-poc'
param vnetName string = 'vnet-agent-factory-poc'
param foundrySubnetName string = 'snet-foundry'
param privateEndpointSubnetName string = 'snet-privateendpoints'
param enableModelDeployment bool = false
param modelDeploymentName string = 'gpt4.1-mini-poc'
param modelName string = 'gpt4.1-mini'
param modelVersion string = '__PENDING_APPROVAL__'
param modelFormat string = 'OpenAI'
param modelSkuName string = 'Standard'
param modelCapacity int = 10

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
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

resource cognitiveServicesDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
}

resource blobDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.blob.core.windows.net'
}

resource keyVaultDns 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.vaultcore.azure.net'
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
    privateDnsZoneIds: {
      cognitiveServices: cognitiveServicesDns.id
      blob: blobDns.id
      keyVault: keyVaultDns.id
    }
    storageAccountName: storageAccountName
    keyVaultName: keyVaultName
    enableModelDeployment: enableModelDeployment
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelVersion: modelVersion
    modelFormat: modelFormat
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
  }
}

output foundryAccountId string = foundry.outputs.foundryAccountId
output foundryProjectId string = foundry.outputs.foundryProjectId
output storageAccountId string = foundry.outputs.storageAccountId
output keyVaultId string = foundry.outputs.keyVaultId
