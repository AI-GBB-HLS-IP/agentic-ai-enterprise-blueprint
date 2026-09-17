# Research: Staged APIM AI Gateway

## Decisions

### Classic Developer and Premium are supported

Premium v2 is the preferred future architecture, but the blueprint retains classic tiers for the
current private gateway. Developer is allowed for cost-conscious smoke tests with capacity one;
Premium remains the production-like default. Both use an undelegated subnet and may require a
Standard static public IP for platform management. The resource does not create a public gateway;
exposure is determined by `virtualNetworkType: Internal`, DNS, and endpoint reachability.

### APIM and Foundry are independent

Azure APIM can be provisioned without a Foundry account. Foundry deployment and customer
enablement have no APIM prerequisite. Combining the resources made approval and permissions for
one service block the other, so the entry points and readiness gates are split.

### Customer APIM network controls are fail-closed

The reviewed customer-approved APIM network profile, whose source revision is retained in the
controlled external evidence location, requires:

- `apimsubnet-*` naming or approved exception;
- approved hybrid NSG;
- `apim-routetable-<location>` or approved exception;
- no delegation;
- Azure Active Directory, Key Vault, SQL, and Storage service endpoints.

Approved external policy evidence may prohibit a route table on a subnet that uses the shared
hybrid NSG. The implementation therefore requires a non-empty exception reference when the
expected route table ID is empty; it does not silently pick one policy over the other.

### Security settings are explicit

The template uses customer-allowed Developer or Premium, corporate publisher metadata, internal
VNet injection, HTTPS-only backends, TLS 1.2+, and disabled legacy protocols/ciphers. This allows
static policy checks before any Azure deployment.

### Diagnostics support policy ownership

The foundation creates AllLogs/AllMetrics diagnostics only in `blueprint` mode. In `policy` mode
it omits that resource, avoiding a conflict with Azure Policy, while live validation requires an
existing setting with the expected workspace and categories. Application Insights and APIM
gateway diagnostics remain blueprint telemetry.

### Capacity monitoring belongs to foundation

An Azure Monitor metric alert on APIM `Capacity` is created at an average threshold greater than
60 percent. This can be validated before any model request exists.

### Foundry governance belongs to integration

Stage 2 requires non-empty GenAI approval and account-enablement evidence, a maintained allowed
region list, private Foundry posture, and model allowlisting. The supplied parameter example
contains placeholders; live validation resolves the actual account and deployment.

### Managed identity and least privilege

The integration template derives the APIM principal from the existing APIM service and assigns
only `Cognitive Services OpenAI User` at the selected Foundry account scope. The backend policy
uses the Cognitive Services audience and no keys or connection strings.

### Enterprise custom DNS is conditional

The private `azure-api.net` zone supports the deployment VNet and linked networks. Broader
enterprise resolution requires separately approved custom domains, CA certificates, and
enterprise DNS A records to the APIM private VIP.

## Deferred or Live-Only Confirmation

- Exact allowed Foundry regions and models must come from the maintained customer policy source.
- Azure what-if needs real resource group names, approved identifiers, and access.
- Policy-owned diagnostics require live inspection.
- Endpoint reachability must be tested from an authorized network location.
- End-to-end request and telemetry evidence requires a deployed, approved Foundry integration.
