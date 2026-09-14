## Why

Live brownfield deployment against a real brownfield target surfaced two concrete gaps between
`infra/envs/poc`/`infra/modules/network` and that target's actual Azure Policy/enforcement
requirements (confirmed by reading the target environment's own internal documentation for
Azure Key Vault, Private Endpoint, and API Management):

1. The target environment enforces that every `apimsubnet-*` subnet be associated with a specific, pre-existing,
   customer-managed route table (`apim-routetable-<location>`) and have four specific service
   endpoints enabled (`Microsoft.AzureActiveDirectory`, `Microsoft.KeyVault`, `Microsoft.Sql`,
   `Microsoft.Storage`). `infra/modules/network/subnets.bicep` has no route-table or
   service-endpoint parameter at all today, so brownfield deployments cannot satisfy this policy
   without a manual portal step after every bicep run.
2. The private DNS zones are managed centrally and live in a separate hub subscription
   (a dedicated hub-network subscription and resource group) and are wired via per-private-endpoint DNS zone groups, never
   VNet-level links. `brownfield-dns.bicep`/`foundry.bicep` already implement this as
   `dnsIntegrationMode=zone-group` (from the prior `2026-09-11-cross-subscription-dns-apim-sizing`
   change), but nothing in the repo's example params or docs spells out, with a concrete worked
   example, that the hub subscription/resource group must be supplied only as
   `dnsSubscriptionId`/`dnsResourceGroupName` and never as the workload deployment scope — this
   caused real deployment confusion this round.

This change closes gap (1) with real Bicep/parameter support and closes gap (2) with a concrete,
named worked example in the generator script defaults/docs so the next brownfield run does not
require guessing. Foundry-account-specific findings (the target environment mandates deploying the Foundry
"standard agent" landing zone via its own ARM template, and Azure OpenAI cannot be self-service
created at all) are explicitly deferred to a follow-up change once network deployment is
confirmed working end-to-end.

## What Changes

- `infra/modules/network/subnets.bicep`: add an optional per-subnet `routeTableId` property (full
  ARM resource ID of a customer-managed route table to associate; never creates or modifies a
  route table, matching the existing NSG-association pattern and FR-018's existing "MAY associate
  an approved existing route table" allowance) and an optional per-subnet `serviceEndpoints` array
  (list of service endpoint names to enable, e.g. `Microsoft.AzureActiveDirectory`).
- `infra/envs/poc/brownfield-network.bicep`: add `apimRouteTableId` (optional, full ARM resource
  ID) and `apimServiceEndpoints` (defaults to the four commonly required endpoints) parameters, wired
  only onto the APIM-purpose subnet.
- `scripts/network/generate-brownfield-params.sh`: add `--apim-route-table-id` CLI flag that
  writes `apimRouteTableId` into the generated brownfield network `.bicepparam`.
- `docs/deploy-00-network.md`: document the new route-table/service-endpoint parameters, and add
  a concrete worked example showing a hub DNS subscription/resource group (naming pattern
  `<hub-subscription-name>` / `<hub-subscription-name>-<workload-alias>`) used only as
  `dnsSubscriptionId`/`dnsResourceGroupName` in `zone-group` mode — never as the workload
  deployment scope.
- `tests/network/test-network-module-contracts.sh` and
  `tests/network/test-generate-brownfield-params.sh`: add regression coverage for the new
  route-table/service-endpoint parameters and CLI flag.

## Capabilities

### New Capabilities
(none — this extends existing brownfield network behavior)

### Modified Capabilities
- `00-network-foundation`: FR-018 already allows associating an approved existing route table in
  brownfield mode but no implementation existed; this change implements that allowance and adds a
  new requirement that brownfield subnets support enabling specific, caller-supplied service
  endpoints (needed to satisfy the APIM subnet's brownfield network policy requirements).

## Impact

- `infra/modules/network/subnets.bicep`, `infra/envs/poc/brownfield-network.bicep`,
  `infra/envs/poc/brownfield-network.bicepparam.example`
- `scripts/network/generate-brownfield-params.sh`
- `docs/deploy-00-network.md`
- `tests/network/test-network-module-contracts.sh`, `tests/network/test-generate-brownfield-params.sh`
- `specs/00-network-foundation/spec.md` (FR-018 clarification + new FR for service endpoints)
- No impact to Foundry, Key Vault, Storage, Cosmos DB, or AI Search modules — those are tracked
  separately per the user's explicit "network first" sequencing decision.
