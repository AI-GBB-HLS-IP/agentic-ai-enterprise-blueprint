# APIM Bicep Module Interface

The implementation should expose a resource-group-scoped APIM module family and an environment
parameter file. This is a design contract, not infrastructure code.

## Required parameters

- `location`, `apimServiceName`, `publisherEmail`, `publisherName`
- Existing IDs: `vnetId`, `apimSubnetId` (subnet to be delegated by this feature)
- Existing Foundry references: `foundryAccountId`, `foundryAccountName`,
  `modelDeploymentName` (`gpt-4.1-mini`)
- `apimSkuCapacity`
- Observability inputs: `logAnalyticsWorkspaceId` (existing or newly created — resolved during
  implementation per research R4), `applicationInsightsName`

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

- The `snet-apim` subnet delegation to `Microsoft.Web/serverFarms` is missing or incorrect
  before APIM creation is attempted.
- The APIM instance would expose a public gateway endpoint (`virtualNetworkType` other than
  `Internal`).
- The Foundry role assignment scope is broader than the single Foundry account.
- The backend policy would reference an API key, connection string, or shared secret instead of
  `authentication-managed-identity`.
- The client-facing API would accept a request without a valid subscription key.
- An MCP server or A2A agent API would be created as part of this module family.
