# APIM Bicep Module Interface

The implementation should expose a resource-group-scoped APIM module family and an environment
parameter file. This is a design contract, not infrastructure code.

## Required parameters

- `location`, `apimServiceName`, `publisherEmail`, `publisherName`
- Existing IDs: `vnetId`, `apimSubnetId` (dedicated subnet that must remain undelegated)
- Existing Foundry references: `foundryAccountName`, `foundryAccountId` (optional; derived from
  `foundryAccountName` in the target resource group when omitted),
  `approvedModels` (public model name, Foundry deployment name, and enabled state; initially
  one `gpt-4.1-mini` entry)
- Network Foundation policy handoff: validated `policyInputs` object containing
  `publicNetworkAccessDisabled: true` and `localAuthDisabled: true`.
- `apimSkuCapacity`
- Observability inputs: `logAnalyticsWorkspaceId` (optional; when omitted/empty, create a new
  workspace; when provided, reuse it per research R4), `applicationInsightsName`

## Approved-model configuration representation

`approvedModels` is the environment-owned source of truth. The API module serializes this array
as JSON, base64-encodes the JSON, and stores it in the non-secret `approved-models` APIM Named
Value. APIM policy decodes the UTF-8 value and parses the JSON array before resolving a client
model name to a Foundry deployment name.

Base64 is used only to transport JSON safely through Named Value substitution and policy XML. It
does not provide confidentiality and must not be used to store credentials. Operators must update
the Bicep parameter and redeploy instead of maintaining a separate live allowlist.

## Outputs

- APIM service resource ID, gateway hostname, and system-assigned managed identity principal ID
- Foundry role assignment resource ID
- Private DNS zone (`azure-api.net`) resource ID and VNet link ID
- Client-facing API resource ID and product/subscription resource ID
- Application Insights and Log Analytics workspace resource IDs
- A structured validation/readiness result distinguishing existing, deployed, pending, and
  failed resources, and explicitly reporting the absence of any MCP/A2A component

## Contract invariants

The module must not create the existing VNet, `snet-privateendpoints`, the existing
`privatelink.azure-api.net` zone, or the Foundry account/project/model deployment. It must fail
closed when:

- The Network Foundation policy handoff is absent, malformed, or contains either boolean as
  `false`; APIM must preserve private access and must not interpret a missing handoff as consent
  to expose a public gateway or enable local authentication.
- The dedicated `snet-apim` subnet does not meet classic Premium VNet injection requirements
  before APIM creation is attempted.
- The APIM instance would expose a public gateway endpoint (`virtualNetworkType` other than
  `Internal`).
- The Foundry role assignment scope is broader than the single Foundry account.
- The backend policy would reference an API key, connection string, or shared secret instead of
  `authentication-managed-identity`.
- The requested public model is absent or disabled in the `approvedModels` configuration.
- The backend deployment name is taken directly from an unvalidated client request instead of
  being resolved through the approved-model configuration.
- The client-facing API would accept a request without a valid subscription key.
- An MCP server or A2A agent API would be created as part of this module family.
