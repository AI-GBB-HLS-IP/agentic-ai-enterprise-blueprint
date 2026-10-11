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
  `privateDnsVnetLinkTags`, `privateDnsDeploymentMode`, `externalDnsValidationReference`.
- Endpoint access (#104): `endpointMode` (`built-in` default, `custom`),
  `endpointAccessPath` (`direct-private` default, `corporate-routed`),
  `customEndpointHostnames` (gateway/developerPortal/management), and
  `endpointValidationEvidence`. Environment variables are `APIM_ENDPOINT_MODE`,
  `APIM_ENDPOINT_ACCESS_PATH`, `APIM_CUSTOM_ENDPOINT_HOSTNAMES`,
  `APIM_ENDPOINT_VALIDATION_EVIDENCE`.
- Certificate handling remains `hostnameMode`, `existingHostnamesJson`,
  `hostnameConfigurations`, and secure `hostnameCertificates`; it does not select endpoints.
  Both foundation files accept `APIM_HOSTNAME_CONFIGURATIONS_JSON` and secret
  `APIM_HOSTNAME_CERTIFICATES_JSON`; the customer example retains individual PFX defaults.
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
- Additive `selectedGatewayHostname`, selected gateway URL, and `endpointAccess` metadata;
  `apimGatewayHostname` stays built-in. Custom `privateDnsHandoff` lists only the three roles
  and legacy portal/SCM client exclusions.

### Endpoint evidence and supported matrix

Built-in/direct-private supports blueprint or external DNS; custom requires external DNS with
direct-private or corporate-routed access. Other combinations fail. Custom selections must
match effective/live endpoint types; no URL, port, path, wildcard, or missing role is accepted.

`endpointValidationEvidence` extends
`../../00-network-foundation/contracts/validation-evidence.md` with exact non-empty string
base fields `validationType`, `status`, `owner`, `scope`, `approvalReference`,
`evidenceSummary`, `timestampUtc`; gate `apim-endpoint-access`, statuses pass/fail/blocked,
and ISO-8601 UTC timestamp (runtime validated, no aliases).
Non-empty extension fields are `apimServiceId`, `endpointMode`, `endpointAccessPath`,
`validationReference`, and `selectedHostnames` (exact three-role string map matching selection).
Corporate access additionally requires `owner: network-owner` and a separate non-placeholder
`routingApprovalReference`. `validationReference` must also be non-placeholder.
Only valid matching pass evidence advances custom readiness; absent evidence is pending,
non-pass cannot advance, and malformed/context-mismatched records fail explicitly.

Base fields remain generic/redacted; live context is confined to untracked deployment inputs,
handoffs, and approved evidence storage. ARM checks structure/context, not external approval
authenticity. Runtime separately measures live binding, DNS, and certificate-validated TLS;
direct access requires equality to live private IPs. Corporate origin requires network-owner
attestation and revalidation after route/service/hostname/certificate changes.

## APIM Service Module

**File:** `infra/modules/apim/main.bicep`

Deploys only `Microsoft.ApiManagement/service` and its system identity. The environment entry
point supplies the service tag object and the ID of its created APIM platform public IP; the
module emits no Foundry parameter, reference, role assignment, or readiness field.

## Stage 2 Entry Point

**File:** `infra/envs/poc/apim-foundry-integration.bicep`

### Inputs

- Existing APIM: `apimResourceGroupName`, `apimServiceName`, `stage1ApimServiceId`,
  `stage1FoundationReadiness`, additive `stage1EndpointAccess` selected metadata,
  `endpointMode`, `endpointAccessPath`, `customEndpointHostnames`.
  The metadata input is `APIM_STAGE1_ENDPOINT_ACCESS`; selection variables match Stage 1.
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
- Selected gateway hostname and client URL preserving `apiPath`.

Stage 2 requires matching selected context, complete passing custom evidence, and a role-matched
live gateway. Overall deployed readiness cannot override invalid endpoint metadata. A legacy
handoff without metadata accepts only built-in/direct-private. Runtime request overrides
(`APIM_INTEGRATION_REQUEST_URL`) require HTTPS, selected host, configured path, no userinfo,
and implicit or explicit port 443, checked before using credentials.

Coverage/acceptance owner: `../../../openspec/changes/support-apim-custom-endpoint-access/design.md`
D5 and tasks 1.1-4.2. Client legacy portal/SCM exclusions do not change platform dependencies,
certificate lifecycle, or Stage 2 resource ownership and private Foundry acceptance.

## Invariants

1. Foundation templates contain no `Microsoft.CognitiveServices` resource/reference and no
   Foundry backend, role, model mapping, product, or governed API.
2. Integration declares APIM as existing and contains no APIM service deployment, private DNS,
   workspace, Application Insights, resource diagnostic setting, or metric alert.
3. The role assignment scope is the selected Foundry account.
4. Backend transport is HTTPS and authentication is managed identity.
5. Foundation and integration readiness are independently reported.
6. Missing governance or customer-policy evidence fails closed rather than selecting defaults.
