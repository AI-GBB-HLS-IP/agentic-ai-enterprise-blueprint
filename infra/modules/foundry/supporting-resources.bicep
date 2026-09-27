// Storage is no longer created here: it is now BYO-capable (create-new-or-reuse-existing) and
// is orchestrated from main.bicep via ./storage.bicep so it can be independently referenced
// cross-subscription/cross-resource-group like AI Search and Cosmos DB. Key Vault remains
// blueprint-owned only (not part of the customer BYO-dependent-resource set).
param location string
param keyVaultName string
param existingKeyVaultResourceId string = ''

@description('Tags to apply to this resource.')
param tags object = {}

var keyVaultPassedIn = !empty(existingKeyVaultResourceId)
var keyVaultParts = split(existingKeyVaultResourceId, '/')
var _validateKeyVaultResourceId = !keyVaultPassedIn || (((length(keyVaultParts) == 9) || (length(keyVaultParts) == 10 && empty(keyVaultParts[9]))) && toLower(keyVaultParts[1]) == 'subscriptions' && toLower(keyVaultParts[3]) == 'resourcegroups' && toLower(keyVaultParts[5]) == 'providers' && toLower(keyVaultParts[6]) == 'microsoft.keyvault' && toLower(keyVaultParts[7]) == 'vaults' && !empty(keyVaultParts[8])) ? true : fail('existingKeyVaultResourceId must be a full ARM resource ID for Microsoft.KeyVault/vaults.')
var keyVaultSubscriptionId = keyVaultPassedIn ? keyVaultParts[2] : subscription().subscriptionId
var keyVaultResourceGroupName = keyVaultPassedIn ? keyVaultParts[4] : resourceGroup().name
var keyVaultNameResolved = _validateKeyVaultResourceId
  ? (keyVaultPassedIn ? keyVaultParts[8] : keyVaultName)
  : ''

resource existingKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (keyVaultPassedIn) {
  scope: resourceGroup(keyVaultSubscriptionId, keyVaultResourceGroupName)
  name: keyVaultNameResolved
}

resource newKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' = if (!keyVaultPassedIn) {
  name: keyVaultName
  location: location
  tags: tags
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

#disable-next-line BCP318
output keyVaultId string = keyVaultPassedIn ? existingKeyVault.id : newKeyVault.id
