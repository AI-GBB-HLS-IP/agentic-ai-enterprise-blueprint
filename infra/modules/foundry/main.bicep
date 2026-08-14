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

@description('Storage account name.')
param storageAccountName string

@description('Key Vault name.')
param keyVaultName string

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

module supportingResources './supporting-resources.bicep' = {
  name: 'foundry-supporting-resources'
  params: {
    location: location
    storageAccountName: storageAccountName
    keyVaultName: keyVaultName
  }
}

module privateEndpoints './private-endpoint.bicep' = {
  name: 'foundry-private-endpoints'
  params: {
    location: location
    privateEndpointSubnetId: privateEndpointSubnetId
    foundryAccountId: account.id
    storageAccountId: supportingResources.outputs.storageAccountId
    keyVaultId: supportingResources.outputs.keyVaultId
    cognitiveServicesDnsZoneId: privateDnsZoneIds.cognitiveServices
    openAiDnsZoneId: privateDnsZoneIds.openAi
    servicesAiDnsZoneId: privateDnsZoneIds.servicesAi
    blobDnsZoneId: privateDnsZoneIds.blob
    keyVaultDnsZoneId: privateDnsZoneIds.keyVault
  }
  dependsOn: [
    project
  ]
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
output storageAccountId string = supportingResources.outputs.storageAccountId
output keyVaultId string = supportingResources.outputs.keyVaultId
// The conditional module is guaranteed to exist when this output is read.
#disable-next-line BCP318
output modelDeploymentId string = enableModelDeployment ? modelDeployment.outputs.deploymentId : ''
