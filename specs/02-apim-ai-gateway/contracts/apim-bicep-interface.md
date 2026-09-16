# Contract: Staged APIM Bicep Interfaces

## Stage 1 Entry Point

**File:** `infra/envs/poc/apim.bicep`

### Inputs

- Deployment: `location`, `apimServiceName`, `publisherEmail`, `publisherName`,
  `apimSkuName`, `apimSkuCapacity`.
- Existing network: `networkResourceGroupName`, `vnetName`, `apimSubnetName`.
- Customer policy: `approvedApimNsgResourceId`, `approvedApimRouteTableResourceId`,
  `routeTableExceptionReference`, `subnetNamingExceptionReference`,
  `requiredServiceEndpoints`.
- APIM platform public IP: `apimPublicIpAddressName`, `apimPublicIpDnsLabel`,
  `apimPublicIpTags`.
- Policy handoff: `publicNetworkAccess`, `diagnosticSettingsOwnership`.
- DNS: `privateDnsZoneName`, `privateDnsRecordName`.
- Monitoring: `applicationInsightsName`, `logAnalyticsWorkspaceId`,
  `logAnalyticsWorkspaceName`, `diagnosticSettingName`, `capacityAlertName`,
  `capacityAlertActionGroupIds`.

No Stage 1 parameter name or value may reference Foundry, models, a backend, product, token limit,
or governed API.

### Outputs

- APIM ID/name/hostname/principal/subnet/private IPs/network mode.
- Public IP resource ID and platform-purpose classification.
- DNS and monitoring resource IDs.
- `foundationReadiness`.
- `integrationReadiness` fixed to `not-deployed`.

## APIM Service Module

**File:** `infra/modules/apim/main.bicep`

Deploys only `Microsoft.ApiManagement/service` and its system identity. The environment entry
point supplies the ID of its created APIM platform public IP; the module emits no Foundry
parameter, reference, role assignment, or readiness field.

## Stage 2 Entry Point

**File:** `infra/envs/poc/apim-foundry-integration.bicep`

### Inputs

- Existing APIM: `apimResourceGroupName`, `apimServiceName`.
- Existing Foundry: `foundryResourceGroupName`, `foundryAccountName`, `foundryAccountId`.
- Governance: `genAiApprovalReference`, `foundryEnablementReference`,
  `customerPolicySource`, `approvedFoundryRegions`, `requirePrivateFoundryAccess`.
- Integration: `approvedModels`, backend/API/product names, `tokenLimitPerMinute`,
  `foundryApiVersion`.

### Outputs

- Existing APIM identity and selected Foundry scope.
- Role assignment, backend, API, product, and model-mapping resource IDs.
- Approved model count and mappings.
- `foundationReadiness` as `existing-reference`.
- `integrationReadiness`.

## Invariants

1. Foundation templates contain no `Microsoft.CognitiveServices` resource/reference and no
   Foundry backend, role, model mapping, product, or governed API.
2. Integration declares APIM as existing and contains no APIM service deployment, private DNS,
   workspace, Application Insights, resource diagnostic setting, or metric alert.
3. The role assignment scope is the selected Foundry account.
4. Backend transport is HTTPS and authentication is managed identity.
5. Foundation and integration readiness are independently reported.
6. Missing governance or customer-policy evidence fails closed rather than selecting defaults.
