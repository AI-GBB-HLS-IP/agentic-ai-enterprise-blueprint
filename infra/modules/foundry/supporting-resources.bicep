// Storage is no longer created here: it is now BYO-capable (create-new-or-reuse-existing) and
// is orchestrated from main.bicep via ./storage.bicep so it can be independently referenced
// cross-subscription/cross-resource-group like AI Search and Cosmos DB. Key Vault remains
// blueprint-owned only (not part of the customer BYO-dependent-resource set).
param location string
param keyVaultName string

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

output keyVaultId string = keyVault.id
