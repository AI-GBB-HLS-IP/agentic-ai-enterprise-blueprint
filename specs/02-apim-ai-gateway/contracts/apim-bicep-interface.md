# Contract: Staged APIM Bicep Interfaces

## Stage 1 Entry Point

**File:** `infra/envs/poc/apim.bicep`

### Inputs

- Deployment: `location`, `apimServiceName`, `publisherEmail`, `publisherName`,
  `apimServiceTags`, `apimSkuName`, `apimSkuCapacity`.
- Existing network: `networkResourceGroupName`, `vnetName`, `apimSubnetName`.
- Customer policy: `approvedApimNsgResourceId`, `approvedApimRouteTableResourceId`,
  `routeTableExceptionReference`, `subnetNamingExceptionReference`,
  `requiredServiceEndpoints`.
- APIM platform public IP: `apimPublicIpAddressName`, `apimPublicIpDnsLabel`,
  `apimPublicIpTags`.
- Policy handoff: `publicNetworkAccess` (Stage 1 permits only `Enabled`),
  `diagnosticSettingsOwnership`, `policyOwnedDiagnosticSettingsValidationReference`.
- DNS: `privateDnsZoneName`, `privateDnsRecordName`, `privateDnsZoneTags`,
  `privateDnsVnetLinkTags`.
- Monitoring: `applicationInsightsName`, `applicationInsightsTags`,
  `logAnalyticsWorkspaceId`, `logAnalyticsWorkspaceName`, `logAnalyticsWorkspaceTags`,
  `diagnosticSettingName`, `capacityAlertName`, `capacityAlertTags`,
  `capacityAlertActionGroupIds`.

### Per-resource tag contract

| Resource | Bicep parameter | Environment variable | Default and ownership |
|---|---|---|---|
| APIM platform public IP | `apimPublicIpTags` | `APIM_PUBLIC_IP_TAGS` | Existing default includes `ProjectCode: APIM`; the blueprint value wins on conflict |
| APIM service | `apimServiceTags` | `APIM_SERVICE_TAGS` | `{}` |
| Created Log Analytics workspace | `logAnalyticsWorkspaceTags` | `APIM_LOG_ANALYTICS_WORKSPACE_TAGS` | `{}`; ignored when an existing workspace ID is supplied |
| Application Insights | `applicationInsightsTags` | `APIM_APP_INSIGHTS_TAGS` | `{}` |
| Capacity alert | `capacityAlertTags` | `APIM_CAPACITY_ALERT_TAGS` | `{}` |
| Blueprint-owned private DNS zone | `privateDnsZoneTags` | `APIM_PRIVATE_DNS_ZONE_TAGS` | `{}`; no resource is created in external DNS mode |
| Blueprint-owned private DNS VNet link | `privateDnsVnetLinkTags` | `APIM_PRIVATE_DNS_VNET_LINK_TAGS` | `{}`; no resource is created in external DNS mode |

Each tag object is independent and passes Azure-valid caller keys and values unchanged, except for
the mandatory public-IP `ProjectCode: APIM` override. The APIM logger and diagnostic children,
Azure Monitor diagnostic setting, and private DNS A records do not expose independent Azure
resource tag inputs.

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
point supplies the service tag object and the ID of its created APIM platform public IP; the
module emits no Foundry parameter, reference, role assignment, or readiness field.

## Stage 2 Entry Point

**File:** `infra/envs/poc/apim-foundry-integration.bicep`

### Inputs

- Existing APIM: `apimResourceGroupName`, `apimServiceName`, `stage1ApimServiceId`,
  `stage1FoundationReadiness`.
- Existing Foundry: `foundryResourceGroupName`, `foundryAccountName`, `foundryAccountId`.
- Governance: `genAiApprovalReference`, `foundryEnablementReference`,
  `customerPolicySource`, `approvedFoundryRegions`.
- Integration: `approvedModels`, backend/API/product names, `tokenLimitPerMinute`,
  `foundryApiVersion`.

### Outputs

- Existing APIM identity and selected Foundry scope.
- Role assignment, backend, API, product, and model-mapping resource IDs.
- Approved model count and mappings.
- `foundationReadiness` as `validated`.
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
