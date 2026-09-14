## Context

See `proposal.md` - Why. Relevant current state:

- `infra/modules/network/subnets.bicep` associates an NSG per subnet via `nsgId` (optional,
  full ARM resource ID) but has no equivalent for route tables or service endpoints.
- `infra/envs/poc/brownfield-network.bicep` already has a mature, three-mode NSG-association
  precedent (`sharedHybridNsgId` / `reuseExistingNsgs` / blueprint-owned) that never creates or
  modifies a customer-owned NSG — only associates it by ID. Route-table association should follow
  the same "never create/modify, only associate an approved existing one" posture, per FR-018.
- `brownfield-dns.bicep` and `foundry.bicep` already implement `dnsIntegrationMode=zone-group`
  with `dnsSubscriptionId`/`dnsResourceGroupName` pointing at a customer-managed hub subscription,
  fully separate from the workload subscription. This already matches the customer's actual
  environment (hub subscription/resource group for centrally-owned Private DNS zones); the gap is
  documentation/examples, not code.

## Goals / Non-Goals

**Goals:**
- Let a brownfield deployer associate one pre-existing, customer-managed route table with the
  APIM-purpose subnet by full ARM resource ID, without creating or modifying any route table.
- Let a brownfield deployer enable specific service endpoints (e.g.
  `Microsoft.AzureActiveDirectory`) on any blueprint-created subnet, defaulting to the four VPCx
  requires on the APIM subnet only.
- Provide one concrete, copy-pasteable worked example (hub subscription/resource group used only
  for `dnsSubscriptionId`/`dnsResourceGroupName`, never as the workload deployment scope) in
  `docs/deploy-00-network.md` so this specific confusion cannot recur.

**Non-Goals:**
- Changing `dnsIntegrationMode`/`zone-group` behavior itself (already correct).
- Any Foundry, Key Vault, Storage, Cosmos DB, or AI Search bicep changes (deferred; see
  proposal.md - Impact).
- Validating that a supplied route table's routes are policy-compliant (out of scope, same as
  existing NSG-ID validation: shape/format only, per FR-018's "customer-managed" posture).

## Decisions

1. **Route table: per-subnet optional property, not a new NSG-style multi-mode system.**
   Unlike NSGs (which have three modes because blueprint-owned NSGs are still a valid POC
   configuration), VPCx route tables are *always* customer-managed per FR-018 ("route tables MUST
   remain customer-managed"). So `subnets.bicep` gets one new optional `routeTableId` subnet
   property (mirroring `nsgId`), and `brownfield-network.bicep` exposes a single
   `apimRouteTableId` parameter (default `''`, meaning "no route table association", matching how
   `existingApimNsgId` defaults to opt-in). No blueprint-owned route table mode is added — greenfield
   mode is unaffected because greenfield's `network/main.bicep` does not touch route tables today
   and this change does not add that.
2. **Service endpoints: a plain string array property, not an enum-validated allow-list.**
   `serviceEndpoints` accepts any array of strings and passes them straight through to the
   `Microsoft.Network/virtualNetworks/subnets` `serviceEndpoints` property (each becomes
   `{ service: <name> }`). Validating against a fixed enum of Azure service-endpoint names would
   need updating every time Azure adds one; Azure's own ARM validation already rejects invalid
   names at deployment time, so client-side enum validation would be redundant defense with a
   maintenance cost and no safety benefit.
3. **`apimServiceEndpoints` defaults to the four VPCx-required values, not empty.** This makes the
   common case (VPCx compliance) the default while still letting a caller pass `[]` to opt out
   for a non-VPCx brownfield target. Alternative considered: make it default to `[]` (matching
   `routeTableId`'s opt-in default) — rejected because, unlike the route table (which needs a
   caller-supplied resource ID that cannot be guessed), the four endpoint names are fixed,
   publicly documented VPCx values with no equivalent "no value supplied" ambiguity, so defaulting
   to them removes a required manual step for every VPCx brownfield deployment without any
   downside for non-VPCx callers (they simply override to `[]`).
4. **Docs-only fix for the DNS hub-subscription confusion**, not a code change. The existing
   `zone-group` mode's validation (`dnsSubscriptionId`/`dnsResourceGroupName` required, and
   explicitly independent from the VNet's own subscription/resource group) already implements the
   correct behavior; re-reading `foundry.bicep`/`brownfield-dns.bicep` confirms there is no
   requirement anywhere that ties the DNS scope to the workload scope in `zone-group` mode. The
   only real gap is that no example in the repo shows this concretely with realistic
   subscription/resource-group naming, which is what caused this round's confusion.

## Risks / Trade-offs

- [Risk] A caller could pass a `routeTableId` that is syntactically valid but points at a route
  table with routes that break connectivity (e.g. missing a default route to the internet for
  APIM control-plane traffic). → Mitigation: this is explicitly the customer's responsibility per
  FR-018 ("route tables MUST remain customer-managed"); the module is not a route-table policy
  validator, consistent with the existing NSG-ID handling. Document the requirement in
  `docs/deploy-00-network.md` and rely on `az deployment group what-if` (already required by
  FR-008/FR-022) to catch it before merge.
- [Risk] Defaulting `apimServiceEndpoints` to VPCx-specific values makes the module slightly
  VPCx-flavored rather than fully generic. → Mitigation: it is a parameter default, fully
  overridable to `[]`; every other blueprint default (subnet CIDRs, NSG naming) is already
  environment-specific in `infra/envs/poc`, so this is consistent with existing precedent, not a
  new pattern.

## Migration Plan

- Additive-only change: `routeTableId` and `serviceEndpoints` are new optional subnet properties
  with safe defaults (`''` / `[]` at the module level); existing callers that don't pass them see
  no behavior change. `apimServiceEndpoints`' non-empty default is the only behavior change for
  existing brownfield callers who re-run against an already-deployed subnet — it will add service
  endpoints to the existing `hybridsubnet-apim` subnet on the next apply. This is called out
  explicitly in `docs/deploy-00-network.md` as a note for anyone re-running against an
  already-deployed APIM subnet.
- No rollback concerns beyond a normal `az deployment group what-if`/re-apply cycle: removing a
  service endpoint or route-table association is itself just another subnet PUT.

## Open Questions

(none - see proposal.md for explicitly deferred, non-blocking follow-up work: Foundry ARM-template
wrapping, Azure OpenAI BYO-only handling, Key Vault/Storage/Cosmos DB policy compliance.)
