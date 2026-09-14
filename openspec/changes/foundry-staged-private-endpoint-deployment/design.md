## Context

See `proposal.md` - Why. `infra/modules/foundry/main.bicep` currently wires everything as one
graph of nested modules inside a single incremental deployment:

1. `account` + `project` (the Foundry account/project resources themselves).
2. `keyVaultResources`, and (if not BYO) `newStorageAccount` / `newAISearchService` /
   `newCosmosDBAccount` — the dependent resources, created with no private endpoint attached yet.
3. `privateEndpoints` — depends on (2) and creates a private endpoint for every resource that
   needs one.
4. `projectConnections`, `cosmosDBRbac`, `aiSearchRbac`, `storageRbac`, `capabilityHost`,
   `modelDeployment` — every one of these already `dependsOn` (directly or transitively)
   `privateEndpoints` in the existing template, because they need working private DNS resolution
   and/or an active data-plane connection to the dependent resources.

So the module graph already has a single natural fault line: everything in (1)-(2) needs to exist
with no private endpoint before a private endpoint can be attached (per the tenant's documented
process), and everything in (3)-(4) needs the private endpoint(s) from (3) to exist and be
approved. Today all of it runs as one `az deployment group create`; the fix is to make (1)-(2) and
(3)-(4) two separately invokable deployments instead of two dependsOn-ordered sections of one.

## Goals / Non-Goals

**Goals:**
- Two independently deployable Bicep entry points: a "base" phase (account, project, and any
  newly created dependent resources — no private endpoints) and a "connectivity" phase (private
  endpoints plus everything currently gated behind them: project connections, RBAC assignments,
  capability host, optional model deployment).
- The connectivity phase takes the base phase's resource IDs/outputs as ordinary input
  parameters — the same shape as the existing BYO-resource-ID inputs — so it does not assume
  those resources are being created in the same deployment operation.
- Both phases remain idempotent (FR-012) and safe to re-run independently.
- Match the existing repo precedent: `infra/envs/poc/brownfield-network.bicep` +
  `brownfield-dns.bicep` already establish the "split an env template into sequential,
  separately-deployed files" pattern for exactly this kind of staged requirement.

**Non-Goals:**
- Changing the BYO input surface, validation rules, or capability-host/model-deployment logic
  themselves — only the deployment *boundary*, not the resource *shape*, changes.
- Solving Key Vault's, Storage's, or Cosmos DB's own compliance details as standalone resources
  (tracked separately per the proposal's Impact section / follow-up specs already discussed).
- Guaranteeing or automating private-endpoint connection approval — if this tenant requires
  manual approval of the Private Link connection, that remains a manual step between running the
  connectivity phase's private-endpoint resources and the rest of that same phase (see Open
  Questions).

## Decisions

1. **Split at the existing `privateEndpoints` dependency boundary**, not at some new boundary.
   The module graph already treats `privateEndpoints` as the one thing every downstream
   construct depends on — it's the natural fault line, requires no new dependency analysis, and
   keeps every existing leaf module (`private-endpoint.bicep`, `project-connections.bicep`,
   `cosmos-rbac.bicep`, etc.) unchanged.
2. **Two separate top-level files, not one file with a phase flag.** Considered a single
   `main.bicep` with a `deployConnectivityPhase bool` parameter gating everything downstream of
   the base resources. Rejected: it requires operators to remember to pass a different flag value
   across two runs of the *same* file, which is more error-prone and less discoverable in the CLI
   and in `docs/` than two distinctly named files. It also breaks from the already-established
   `brownfield-network.bicep`/`brownfield-dns.bicep` precedent for the same class of problem.
3. **Base-phase outputs become connectivity-phase inputs, treated like BYO resource IDs.** The
   connectivity phase's Storage/Search/Cosmos/Foundry-account parameters are the same
   full-ARM-resource-ID shape already used for BYO resources today — whether the ID came from the
   base phase's outputs or from a genuinely pre-existing BYO resource is indistinguishable to the
   connectivity phase, which is exactly the property we want (no assumption about co-deployment).
4. **Leaf modules are reused unchanged.** No changes needed inside `private-endpoint.bicep`,
   `project-connections.bicep`, `cosmos-rbac.bicep`, `ai-search-rbac.bicep`, `storage-rbac.bicep`,
   `capability-host.bicep`, or `model-deployment.bicep` — only the orchestrating entry point
   changes.
5. **`Microsoft.Resources/deployments` nested-template wrapping was considered and rejected** as
   the mechanism for enforcing the two-phase gate (e.g., an explicit "wait for approval" nested
   deployment resource). It adds complexity without benefit here: the customer's own workflow is
   already two separate manual/CLI actions with a human check in between, and a CLI-level
   two-file split reproduces that directly without needing ARM-level orchestration primitives.

## Risks / Trade-offs

- [Risk] Operators run the connectivity phase before the base phase finishes or before its
  resource IDs are copied over correctly → [Mitigation] Connectivity-phase parameters use the
  same ARM-resource-ID shape validation (`fail()` guards) already used for BYO inputs, so a
  missing/malformed ID fails fast with a clear message rather than silently deploying against the
  wrong resource.
- [Risk] The two files can drift out of sync — e.g., a new BYO parameter added to the base phase
  is forgotten in the connectivity phase's passthrough → [Mitigation] add contract tests (mirrors
  `tests/network/test-network-module-contracts.sh`) asserting every base-phase output has a
  corresponding connectivity-phase input.
- [Risk] **BREAKING** for any caller of the current single combined `foundry.bicep` →
  [Mitigation] confirm during task execution whether any live/POC environment depends on the
  combined path before removing it; if so, keep it available as an explicit "non-brownfield /
  low-restriction only" alternative rather than deleting outright.
- [Risk] Private-endpoint connection approval may be a manual, asynchronous step in this tenant
  (FR-006 already requires an "approved connection state" before validation passes) → the
  connectivity phase could partially apply with endpoints stuck in `Pending` →
  [Mitigation] preserve the existing FR-006 validation check as the gate before running the rest
  of the connectivity phase's downstream modules; if live testing shows approval is genuinely
  asynchronous, a follow-up may be needed to further split the connectivity phase (see Open
  Questions - not resolved here to avoid guessing at tenant behavior we have not yet observed).

## Migration Plan

1. Extract the current `infra/modules/foundry/main.bicep` into two orchestration entry points:
   `base.bicep` (account, project, `keyVaultResources`, and BYO-or-new resolution + creation of
   Storage/AI Search/Cosmos DB — no private endpoints) and `connectivity.bicep` (`privateEndpoints`
   onward: project connections, RBAC, capability host, optional model deployment).
2. Add matching env-level entry points `infra/envs/poc/foundry-base.bicep` +
   `.bicepparam.example` and `infra/envs/poc/foundry-connectivity.bicep` + `.bicepparam.example`,
   following the `brownfield-network.bicep`/`brownfield-dns.bicep` naming precedent.
3. Update `scripts/foundry/deploy.sh`, `preflight.sh`, `what-if.sh` to drive the two phases as
   sequential, separately invokable steps.
4. Update the Foundry deployment guide in `docs/` with the exact two-step sequence, the rationale
   (tenant policy requires the base resource to exist, unconnected, before a private endpoint is
   attached), and a note that connection approval may need to be manually confirmed between
   phases.
5. Decide the fate of the old combined `foundry.bicep` (deprecate with a note, restrict to
   non-brownfield use, or remove) based on whether anything currently depends on it — this is a
   task-time decision, not a design-time one, since it depends on current repo/consumer state.

Rollback: reverting these Bicep/script/doc changes does not by itself undo already-created Azure
resources (Bicep/ARM deployments are declarative), and no destructive resource action is
introduced by this migration itself, so rollback is a plain revert of the changed files.

## Open Questions

- Does this tenant's private-endpoint connection auto-approve for same-tenant Private Link
  services, or does it require manual admin approval? If manual, the connectivity phase may need
  a further internal split (create private endpoints → wait for approval → create everything
  else) discovered during live validation, similar to how the network fix's exact policy behavior
  was only confirmed by testing against the real tenant.
- Should the old single-shot `foundry.bicep` be removed, kept as a greenfield-only alternate
  path, or deprecated with a warning? To be resolved once current callers/consumers are confirmed
  during task execution.
