## Context

See `proposal.md` - Why. The authoritative references for the required process are the approved
reference ARM template and deployment guide:

- **Phase 2** (single ARM deployment): creates the Foundry account/project, the BYO-or-new
  Storage/AI Search/Cosmos DB resources, bare `Microsoft.Network/privateEndpoints` for all of
  them (Foundry account, Storage, Key Vault, Cosmos DB, AI Search) with **no**
  `privateDnsZoneGroups` child resource, plus RBAC assignments and the capability host — verified
  directly from the reference template's nested deployments (`private-endpoint-deployment`
  contains bare `Microsoft.Network/privateEndpoints` resources and no DNS zone group children).
- **Phase 3** (separate, later, manual): the end user associates each already-created private
  endpoint with its private DNS zone, one resource at a time, via the Azure Portal.

This confirms a deployment can complete ARM-plane calls (account creation, RBAC assignment,
capability host activation) without the private endpoints having a DNS zone group yet — those
calls are control-plane and do not require live data-path name resolution to succeed. DNS zone
group association is only needed later, for the Agent runtime itself to resolve and reach the
privately-networked resources.

Today, `infra/modules/foundry/private-endpoint.bicep` creates both the bare private endpoint AND
its `privateDnsZoneGroups` child resource in the same resource block, and
`infra/modules/foundry/main.bicep` threads `privateDnsZoneIds` all the way through from
`infra/envs/poc/foundry.bicep`. The fix is to separate DNS zone group creation into its own
module and its own deployable env-level entry point, matching the approved Phase 2 / Phase 3
boundary — but keep it Bicep-templated (not a manual Portal click-through) for
repeatability, consistent with this repo's `brownfield-network.bicep` + `brownfield-dns.bicep`
precedent for the same class of problem.

## Goals / Non-Goals

**Goals:**
- `infra/modules/foundry/main.bicep` keeps creating the account, project, dependent resources,
  and bare private endpoints together in one deployment — unchanged in spirit from today, minus
  the DNS zone group resources and the `privateDnsZoneIds` parameter.
- A new, independently deployable "DNS association" entry point
  (`infra/modules/foundry/private-endpoint-dns.bicep` + `infra/envs/poc/foundry-dns.bicep`) creates
  the `privateDnsZoneGroups` child resources against already-existing private endpoints,
  referenced by full resource ID.
- The DNS phase takes full private-endpoint resource IDs as ordinary input parameters — the same
  shape whether an endpoint was created by the main deployment or supplied independently — so it
  does not assume co-deployment, subscription, resource group, or endpoint naming.
- Both phases remain idempotent (FR-012) and safe to re-run independently.
- Match the existing repo precedent: `infra/envs/poc/brownfield-network.bicep` +
  `brownfield-dns.bicep` already establish the "split an env template into sequential,
  separately-deployed files" pattern for exactly this kind of staged requirement.

**Non-Goals:**
- Changing the BYO input surface, validation rules, or capability-host/model-deployment logic
  themselves — only the private-endpoint/DNS-zone-group boundary changes.
- Adopting the approved reference ARM template as our deployment artifact — we keep our own
  Bicep modules, matching that template's *behavioral* split (bare PE creation vs. DNS zone group
  association) rather than replacing our tooling with it.
- Automating the approved manual Phase 3 Portal step in the sense of removing operator judgment —
  `foundry-dns.bicep` is a scripted equivalent of that manual step, not a bypass of it; operators
  still choose when to run it.

## Decisions

1. **Split at the private-endpoint / DNS-zone-group boundary inside `private-endpoint.bicep`**,
   not at the account/private-endpoint boundary. Verified against the approved reference template:
   private endpoints ARE created in the same deployment as the account; only DNS zone group
   association is deferred. Splitting anywhere else would not match the approved process (see
   proposal's Why).
2. **Two separate files, not one file with a phase flag.** Same reasoning as the network
   precedent: two distinctly named, independently deployable files are clearer to operators and
   CI than a single file gated by a boolean flag.
3. **DNS-phase inputs are full private-endpoint resource IDs.** The resource ID is the stable
   interface between phases and supports private endpoints created by the main deployment or
   supplied independently, including endpoints in another resource group or subscription. The
   DNS module derives the existing endpoint scope and name from each non-empty ID before creating
   its `privateDnsZoneGroups` child resource.
4. **Leaf modules for RBAC, project connections, capability host, and model deployment are
   unchanged.** None of them create or depend on DNS zone groups directly — they depend on the
   `privateEndpoints` module only for deployment ordering, which is unaffected by removing the
   DNS zone group resources from that module.
5. **Empty PE resource-ID parameters skip DNS zone group creation for that resource,** mirroring
   the existing `existing*PrivateEndpoint` opt-out semantics — if a dependency uses a separately
   managed endpoint whose DNS association must not be changed, there is nothing for this DNS
   phase to attach for that resource.

## Risks / Trade-offs

- [Risk] Operators run `foundry-dns.bicep` before the main Foundry deployment's private endpoints
  exist, or pass an invalid PE resource ID → [Mitigation] `private-endpoint-dns.bicep` references
  each PE as an `existing` resource at the scope encoded in the ID; Azure fails the deployment
  immediately with a clear resource error rather than silently no-op'ing.
- [Risk] Skipping `foundry-dns.bicep` entirely leaves private endpoints without DNS resolution,
  and downstream calls that depend on it (project connections, capability host activation) may
  still succeed at the ARM/control-plane layer while the Agent runtime itself cannot resolve the
  dependent resources at execution time → [Mitigation] document prominently in the Foundry
  deployment guide that the DNS phase is required for the deployment to be functionally complete,
  even though the main deployment will report success without it (matches the approved
  Phase 2 "succeeds" / Phase 3 "required before use" distinction).
- [Risk] **BREAKING** for any caller relying on `main.bicep`'s current `privateDnsZoneIds`
  parameter → [Mitigation] this is the intended, documented breaking change; the migration plan
  below removes it in the same change that adds the replacement DNS phase.

## Migration Plan

1. Remove the `privateDnsZoneGroups` child resources and their DNS-zone-ID parameters from
   `infra/modules/foundry/private-endpoint.bicep`; preserve outputs for each private endpoint's
   full resource ID.
2. Add `infra/modules/foundry/private-endpoint-dns.bicep`: takes each dependency's full PE
   resource ID (empty to skip) plus its DNS zone ID, and creates the corresponding
   `privateDnsZoneGroups` child resource against the already-existing PE at the encoded scope.
3. Update `infra/modules/foundry/main.bicep` to stop threading `privateDnsZoneIds` through to
   `private-endpoint.bicep`, and to surface the PE resource-ID outputs.
4. Update `infra/envs/poc/foundry.bicep` to drop DNS zone resolution (the `dnsIntegrationMode`
   parameters, zone lookups, and `servicesAi` zone/VNet-link creation) — that logic moves to the
   new `infra/envs/poc/foundry-dns.bicep`, mirroring `brownfield-network.bicep`'s DNS-free scope.
5. Add `infra/envs/poc/foundry-dns.bicep` + `.bicepparam.example`, wrapping
   `private-endpoint-dns.bicep`, taking the main deployment's PE resource-ID outputs (or
   independently supplied PE resource IDs) as inputs alongside the same DNS zone resolution
   logic removed from `foundry.bicep` in step 4.
6. Use the existing `TEMPLATE_FILE`/`PARAMETER_FILE` overrides in
   `scripts/foundry/deploy.sh` and `scripts/foundry/what-if.sh` to invoke the main and DNS
   deployments separately. Keep `scripts/foundry/preflight.sh` as the shared prerequisite check;
   it does not consume template or parameter file overrides.
7. Update the Foundry deployment guide and `tests/network/test-brownfield-poc-smoke.sh` (which
   currently asserts the zone-group DNS validation lives in `foundry.bicep`) to point at the new
   `foundry-dns.bicep` instead.

Rollback: reverting these Bicep/script/doc changes does not by itself undo already-created Azure
resources (Bicep/ARM deployments are declarative), and no destructive resource action is
introduced by this migration itself, so rollback is a plain revert of the changed files.

## Open Questions

- Do the target environment's private-endpoint connections auto-approve for same-directory
  Private Link services, or do they require manual admin approval independent of the DNS zone
  group timing addressed here? If manual, a further split inside the DNS phase (or a wait step)
  may be needed, to be confirmed by live testing.
