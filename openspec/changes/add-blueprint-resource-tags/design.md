## Context

See `proposal.md` for motivation. The archived APIM tagging change established separate tag
objects, empty defaults, opaque caller values, mandatory public IP tag precedence, and strict
blueprint-ownership boundaries. Outside APIM, the current implementation is inconsistent:

- greenfield network resources and optional Bastion resources expose no tag inputs;
- brownfield network deployment conditionally creates NSGs but references the customer VNet,
  route table, and reusable NSGs as external resources;
- greenfield private DNS creates multiple zones and links without tags, while brownfield DNS may
  create only links or attach zone groups to existing private endpoints;
- Foundry uses one shared `tags` object for the account, project, supporting services, and private
  endpoints, with Storage, AI Search, and Cosmos DB each optionally supplied as existing resources;
- APIM Stage 1 already has independent tags, while Stage 2 primarily creates role assignments and
  APIM child resources that do not expose independent Azure resource tags.

The design must preserve existing Foundry callers and must not make live Foundry approval a
prerequisite for proving offline tag contracts.

## Goals / Non-Goals

**Goals:**

- Produce an auditable inventory of blueprint-created resources, ownership conditions, and ARM tag
  support.
- Give each taggable logical resource an independent caller-controlled tag object.
- Preserve existing Foundry shared-tag behavior while allowing resource-specific overrides.
- Use the same logical tagging contract in greenfield and brownfield paths when they create the same
  resource type.
- Prove resource-to-tag wiring and exclusion of referenced existing/BYO resources from tag
  assignments through compiled-template tests, without claiming to prove ownership in Azure.

**Non-Goals:**

- Retagging existing customer resources or inheriting resource-group tags implicitly.
- Adding metadata properties to resource types that do not support Azure resource tags.
- Changing the staged APIM/Foundry deployment boundary or resolving its separate evidence-file
  reconciliation.
- Making customer Foundry approval available or treating blocked live validation as successful.
- Defining a mandatory enterprise tag taxonomy beyond existing blueprint-controlled invariants.
- Automatically discovering resource ownership or undeclared name collisions, adopting unrelated
  resources, or enforcing concurrency safety.
- Adding ownership manifests, attestation/evidence files, freshness gates, or deployment wrappers.

## Decisions

### Build a checked resource inventory before changing interfaces

Implementation will first classify every resource declaration by logical owner, creation
condition, and tag support:

In this inventory, "blueprint-created" includes create/update declarations used to redeploy
previously blueprint-created resources. It describes declared management intent, not proof that a
resource name is absent or owned in Azure.

- **blueprint-created and taggable** — receives an explicit tag input;
- **blueprint-created but not independently taggable** — documented as unsupported;
- **existing or externally supplied** — receives no tag assignment;
- **conditional create-or-reference** — receives tags only on the create branch.

The inventory will cover all environment entry points and modules, including both APIM stages.
Each row will link the entry point, resource identity/scope, active create/update or reference
condition, tag input/default/precedence (or unsupported reason), implementation task, and acceptance
scenario. Task 1.1 establishes this matrix and task 6.1 publishes the same inventory, not a second
independently maintained list.
This is preferred over adding parameters opportunistically because missed conditional paths could
silently retag external resources or leave blueprint-owned resources ungoverned.

### Use explicit singular inputs and purpose-keyed maps for repeated families

Singular resources will use descriptive object parameters such as `virtualNetworkTags`,
`foundryAccountTags`, or `bastionHostTags`, each defaulting to `{}`. Repeated homogeneous families
will use purpose-keyed objects whose values are independent tag objects, for example logical maps
for private DNS zones, private DNS links, and private endpoints.

This preserves the APIM principle of independent resource tags without creating an unmaintainable
flat parameter list for every repeated DNS or endpoint instance. A single universal blueprint tag
object was rejected because it hides ownership and prevents resource-specific governance. A fully
flat list for every repeated instance was rejected because it duplicates the logical resource keys
already used by the modules and parameter contracts.

Missing keys in a repeated-family map resolve to `{}`. Each map's accepted key set is scoped to the
logical resources its owning entry point actually creates. The Foundry services.ai zone and link
are intentionally not a row in this table; they use separate singular inputs described below the
table.

| Entry point / DNS mode | Repeated family | Accepted keys |
|---|---|---|
| Greenfield `infra/modules/network/private-dns.bicep` | Private DNS zones | `cognitiveServices`, `azureOpenAI`, `apim`, `keyVault`, `storageBlob`, `sql`, `cosmosDB`, `aiSearch` |
| Greenfield `infra/modules/network/private-dns.bicep` | Private DNS virtual network links | `cognitiveServices`, `azureOpenAI`, `apim`, `keyVault`, `storageBlob`, `sql`, `cosmosDB`, `aiSearch` |
| Brownfield `infra/envs/poc/brownfield-dns.bicep` (`vnet-link` mode) | Private DNS virtual network links | `cognitiveServices`, `azureOpenAI`, `keyVault`, `storageBlob`, `cosmosDB`, `aiSearch` |
| Brownfield `infra/envs/poc/brownfield-dns.bicep` (`zone-group` mode) | Private DNS virtual network links | empty — parameter must be omitted or `{}` |
| Foundry creation path `infra/envs/poc/foundry.bicep` -> `infra/modules/foundry/main.bicep` -> `infra/modules/foundry/private-endpoint.bicep` | Foundry private endpoints | `foundry`, `storage`, `keyVault`, `cosmosDB`, `aiSearch` |

`brownfield-dns.bicep` is a single template shared by both `dnsIntegrationMode` values, so its link
tag map parameter is always declared. In `zone-group` mode the template creates no VNet link
modules, so the parameter's accepted-key set is empty in that mode and any submitted key fails
validation the same way an unsupported key would in `vnet-link` mode. The parameter's `@description`
will state this explicitly — that in `zone-group` mode the parameter must be omitted or left `{}` —
so callers do not submit `vnet-link`-mode keys and hit a confusing failure.

Brownfield DNS never creates the `apim` or `sql` zone links. Its six Foundry-required links are
`cognitiveServices`, `azureOpenAI`, `keyVault`, `storageBlob`, `cosmosDB`, and `aiSearch`; `apim`
and `sql` are valid only for the greenfield map and are rejected by the brownfield entry point's
`fail()` check like any other unsupported key. The services.ai private DNS zone and virtual network
link are not members of any repeated-family map; the Foundry DNS entry point exposes them through
separate singular `servicesAiPrivateDnsZoneTags` and `servicesAiPrivateDnsVnetLinkTags` inputs.

The Foundry private-endpoint map belongs exclusively to the Foundry creation path, because
`foundry-dns.bicep` never creates private endpoints: it receives already-created endpoint IDs and
creates only DNS zone-group children for them. `foundry-dns.bicep` therefore exposes no
private-endpoint tag input at all; its tag surface is limited to the shared `tags` base plus the
two services.ai zone/link inputs above. Endpoints are created by
`infra/modules/foundry/private-endpoint.bicep` through `infra/modules/foundry/main.bicep`, so the
map is declared on `infra/envs/poc/foundry.bicep` and threaded down that path only.

Every entry point derives the supplied keys from `items(map)`, filters out its accepted family key
set, and calls `fail()` when any keys remain. `brownfield-dns.bicep` selects that set from
`dnsIntegrationMode`: the six-key set for `vnet-link` and the empty set for `zone-group`. The stable
error format is
`<parameterName> contains unsupported logical resource key(s): <keys>` so tests can assert both the
affected map and rejected keys. Unknown keys are never silently dropped.

### Preserve the Foundry shared tag input as a compatibility base

The existing Foundry `tags` object remains supported as the base tag set. Each new
resource-specific Foundry tag object defaults to `{}` and is merged as:

```text
effective tags = union(existing shared tags, resource-specific tags)
```

Bicep `union()` gives later arguments precedence, so the resource-specific value wins on duplicate
keys. Existing callers therefore retain current tag behavior, while new callers can differentiate
the account, project, Key Vault, Storage, AI Search, Cosmos DB, and each private endpoint created
by the Foundry creation path, plus the services.ai private DNS zone and virtual network link created
by `foundry-dns.bicep`. In `vnet-link` mode, the existing shared `tags` object is the base for both
services.ai DNS resources and their separate resource-specific tag objects override duplicate keys.
In `zone-group` mode, `foundry-dns.bicep` creates neither the services.ai zone nor its virtual
network link, so neither resource-specific input applies and no tag update is emitted. Any
documented mandatory blueprint tags are applied as the final merge layer described in the next
decision.

Removing or changing the meaning of `tags` was rejected as a breaking change. Applying the shared
object after the resource-specific object was rejected because it would prevent explicit overrides.

### Keep mandatory blueprint tags as the final merge layer

Where a resource already has a documented mandatory tag, the merge order remains:

```text
legacy/base tags -> resource-specific tags -> mandatory blueprint tags
```

This preserves the APIM public IP `ProjectCode: APIM` invariant. No new mandatory tags are
introduced by this change.

### Respect declared ownership without claiming ownership discovery

**Decision:** This capability provides tagging under declared ownership, not automatic proof of
ownership. Tag expressions appear only on blueprint-managed create/update declarations, including
redeployments of previously blueprint-created resources. Resources referenced through
existing-resource or BYO paths receive no blueprint tag assignment. Conditional paths pass tags
only into the active create/update branch.

| Resource situation | Tagging behavior |
|---|---|
| Existing-resource or BYO reference | No blueprint tag assignment to the referenced resource |
| New resource on a blueprint-managed create/update path | Apply its effective tag inputs |
| Previously blueprint-created resource redeployed on that path | Apply current effective tags using the same merge precedence; no new ownership evidence input |
| Determinable contradiction between a supplied external ID and an active create/update target | Reject the contradictory inputs |
| Undeclared unrelated resource occupying the target identity | Not detected by this capability; ARM may update it |

For private endpoints, tagging belongs to the Foundry creation path; `foundry-dns.bicep` passes no
endpoint tags because it references endpoint IDs for DNS zone-group associations. Its services.ai
zone/link create/update declarations retain their own supported tag inputs.

**Operator prerequisite and accepted residual risk:** Before deploying, operators must verify that
each create/update target in the actual Azure cloud, subscription, resource group, resource type,
and name is either absent or already blueprint-owned. They must prevent conflicting concurrent
deployments through their operational controls. If ownership cannot be established, they must stop
or select a supported existing-resource/BYO path rather than adopt an unrelated resource through
the create/update path.

ARM is create-or-update: selecting a create branch, choosing a deterministic name, or compiling
successfully does not prove ownership. An incorrect declaration or another actor creating the
target after the operator's check can cause an unrelated resource to be retagged. This capability
does not detect or prevent that collision or race and does not promise that external resources can
never be retagged regardless of caller inputs or concurrent activity.

**In-template input consistency:** Reject contradictions determinable from supplied inputs and
active branches with `fail()`. Compare full resource identities (scope, type, and name), not bare
names, using case-insensitive ARM ID comparison. In brownfield network, an
`existingApimNsgId` or `existingComputeNsgId` identifying an NSG that the active NSG module will
create/update is contradictory when `sharedHybridNsgId` is empty and `reuseExistingNsgs` is
`false`. Either supplied ID must be checked against both active NSG targets, not only the
same-purpose target. An identically named NSG in a different subscription or resource group is
not the same resource. A non-empty `sharedHybridNsgId` suppresses that module and must not be
rejected by this check. Other conditional paths use the same active-target rule where applicable;
do not invent a contradiction where an existing ID already disables creation. Ensure the guard is
consumed by an evaluated expression so compilation cannot discard it as unused.

This is an intentional compatibility exception for previously tolerated contradictory inputs,
including when new tag inputs are omitted. Valid shared/reuse configurations and non-contradictory
parameter files remain supported; task 6.2 documents how to correct an affected caller's
create/reuse selection rather than silently accepting a conflicting ownership declaration.

Task 2.7 implements input-consistency validation. Tasks 5.6-5.7 cover contradictions, valid reference
branches, and ordinary redeployments. These checks prove branch/tag wiring and declared-input
consistency, not live Azure ownership.

| Ownership obligation | Implementation/documentation tasks | Acceptance coverage |
|---|---|---|
| Exclude existing/BYO references from tag assignments | 2.4-2.5, 3.2-3.4, 4.1 | Spec brownfield/Foundry/DNS reference scenarios; tests 4.3, 5.1-5.2 |
| Preserve normal managed-resource redeployment | 1.4, 3.1, 4.1 | Spec redeployment scenario; test 5.7 |
| Reject determinable input contradictions, without rejecting inactive targets or different scopes | 2.7 | Spec contradiction, different-scope, and shared-NSG scenarios; test 5.6 |
| Make operator prerequisites and collision/concurrency limitations explicit | 6.2 | Spec operator-guidance and undeclared-collision scenarios |
| Include all entry points, including APIM Stage 1 | 1.1, 6.1 | Spec inventory requirement; matrix reconciliation and tests 4.3, 5.1-5.3 |

**Entry-point coverage:** The inventory and operator guidance include `infra/envs/poc/main.bicep`
(private DNS and optional Bastion included), `brownfield-network.bicep`, `brownfield-dns.bicep`,
`foundry.bicep`, `foundry-dns.bicep`, and `apim.bicep` under the same directory. APIM Stage 1
retains all existing tag mappings and follows the same declared-ownership boundary. Stage 2
`apim-foundry-integration.bicep` remains inventoried for unsupported tag surfaces; no synthetic tag
inputs or ownership gate are added.

**Scope decision:** Automatic ownership discovery, adoption/attestation, ownership manifests,
evidence files, freshness limits, deployment wrappers, locks, and name reservations are not part of
this change or a new prerequisite for it. The earlier proposed ownership preflight is superseded
by this decision, not deferred as an unresolved implementation task. A separate capability may
define automated safeguards if required later. Existing network/Foundry preflights and their
unrelated prerequisites remain unchanged. Task 6.2 documents operator responsibilities for both
scripted and direct deployment procedures without adding a new gate.

### Treat unsupported child and extension resources as documentation, not fake inputs

The inventory and deployment contracts will explicitly identify unsupported tag surfaces. Known
examples include role assignments, subnets, private DNS records and private endpoint DNS zone
groups, Azure Monitor diagnostic settings, APIM loggers/diagnostics/backends/named values/APIs/
operations/products/bindings/policies, and Foundry child resources whose selected API does not
expose tags.

The implementation will verify actual tag support against the compiled resource schema before
finalizing this list. Synthetic tag parameters or unrelated metadata fields were rejected because
they would imply governance behavior Azure does not provide.

### Validate offline contracts independently from live approval

Tests will compile each affected entry point and assert:

- every supported parameter reaches only its intended resource;
- defaults preserve existing callers;
- Foundry base and resource-specific merge precedence is correct;
- mandatory APIM tag precedence is unchanged;
- external/BYO paths contain no tag update;
- greenfield and brownfield modes apply tags only on their declared create/update branches;
- previously blueprint-created resources use the same tag inputs and merge rules on redeployment;
- determinable contradictory ownership inputs fail while valid reference branches remain accepted;
- unsupported resources do not gain misleading tag inputs.

Foundry live what-if and runtime evidence remain `BLOCKED` when approval or an authorized
environment is unavailable. Offline success does not convert those gates to `PASS`, and the
separate Stage 1 evidence-file inconsistency is not modified by this change.

## Risks / Trade-offs

- **[Risk] The expanded interface contains many tag inputs.** → Use consistent resource-oriented
  names, purpose-keyed maps for repeated families, one contract table, and generated/targeted
  assertions where practical.
- **[Risk] Legacy Foundry shared tags can obscure which layer supplied a value.** → Document merge
  precedence and assert it with conflicting-key regression fixtures.
- **[Risk] ARM tag support differs across parent, child, and preview API versions.** → Verify each
  resource type against compilation and compiled output before exposing an input.
- **[Risk] Conditional BYO paths could accidentally receive tags.** → Keep existing declarations
  tag-free and add create-versus-reference compiled-template assertions.
- **[Risk] Azure Policy can append or replace tags after deployment.** → Validate the submitted
  deployment contract separately from policy-added live state.
- **[Risk] Tag examples could expose customer metadata.** → Use only generic sanitized keys and
  values and include confidentiality checks in regression coverage.
- **[Accepted risk] ARM create-or-update could retag an undeclared customer resource at the target
  identity, including one created concurrently after an operator check.** Operators must verify
  ownership and prevent conflicting concurrent deployments; this capability does not enforce
  those responsibilities. Input-consistency checks reject only determinable contradictions, not
  undisclosed Azure collisions. Task 6.2 documents this boundary without promising automatic
  ownership proof.
- **[Trade-off] Purpose-keyed maps are less discoverable than singular parameters.** → Publish the
  accepted logical keys and defaults in parameter contracts and customer examples.

## Migration Plan

1. Complete and review the resource ownership/tag-support inventory.
2. Add backward-compatible tag inputs to environment and module interfaces.
3. Preserve the Foundry shared `tags` input and layer resource-specific overrides over it.
4. Apply effective tags only to declared blueprint-managed, taggable create/update targets.
5. Update `.bicepparam` environment-variable contracts and sanitized examples.
6. Add compiled-template, parameter, merge-precedence, and ownership-boundary regression tests.
7. Update deployment documentation with supported/unsupported tag surfaces, operator ownership
   prerequisites, normal redeployment behavior, and the accepted collision/concurrency risk.
8. Run all offline builds and validation suites; record approval-dependent Foundry live gates as
   `BLOCKED`.

Rollback removes the new optional resource-specific inputs and assignments while retaining the
legacy Foundry shared tag contract and existing APIM behavior. Tags already applied in Azure may
remain until explicitly changed because tag rollback follows normal ARM update semantics.
