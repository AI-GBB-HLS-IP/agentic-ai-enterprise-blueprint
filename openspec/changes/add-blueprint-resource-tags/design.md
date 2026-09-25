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
- Prove resource-to-tag wiring and external-resource protection through compiled-template tests.

**Non-Goals:**

- Retagging existing customer resources or inheriting resource-group tags implicitly.
- Adding metadata properties to resource types that do not support Azure resource tags.
- Changing the staged APIM/Foundry deployment boundary or resolving its separate evidence-file
  reconciliation.
- Making customer Foundry approval available or treating blocked live validation as successful.
- Defining a mandatory enterprise tag taxonomy beyond existing blueprint-controlled invariants.

## Decisions

### Build a checked resource inventory before changing interfaces

Implementation will first classify every resource declaration by logical owner, creation
condition, and tag support:

- **blueprint-created and taggable** — receives an explicit tag input;
- **blueprint-created but not independently taggable** — documented as unsupported;
- **existing or externally supplied** — receives no tag assignment;
- **conditional create-or-reference** — receives tags only on the create branch.

The inventory will cover all environment entry points and modules, including both APIM stages.
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

Brownfield DNS never creates the `apim` or `sql` zone links (`brownfield-dns.bicep` links only the
six Foundry-required zones), so those keys are valid only for the greenfield map and are rejected
by the brownfield entry point's `fail()` check like any other unsupported key. The services.ai
private DNS zone and virtual network link are not members of any repeated-family map; the Foundry
DNS entry point exposes them through separate singular `servicesAiPrivateDnsZoneTags` and
`servicesAiPrivateDnsVnetLinkTags` inputs.

The Foundry private-endpoint map belongs exclusively to the Foundry creation path, because
`foundry-dns.bicep` never creates private endpoints: it receives already-created endpoint IDs and
creates only DNS zone-group children for them. `foundry-dns.bicep` therefore exposes no
private-endpoint tag input at all; its tag surface is limited to the shared `tags` base plus the
two services.ai zone/link inputs above. Endpoints are created by
`infra/modules/foundry/private-endpoint.bicep` through `infra/modules/foundry/main.bicep`, so the
map is declared on `infra/envs/poc/foundry.bicep` and threaded down that path only.

Every entry point derives the supplied keys from `items(map)`, filters out its accepted family key
set, and calls `fail()` when any keys remain. The stable error format is
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

### Enforce creation ownership at the resource declaration

Tag expressions will appear only on declarations that create resources. Existing-resource
declarations remain tag-free. Conditional create-or-reference paths for Storage, AI Search, Cosmos
DB, NSGs, DNS, and private endpoints will pass tags only into the create branch. For private
endpoints this is the Foundry creation path; `foundry-dns.bicep`, which only associates existing
endpoint IDs with DNS zone groups, passes no endpoint tags at all.

ARM deployments are create-or-update, so a non-`existing` declaration with a deterministic
blueprint-owned name (for example brownfield's `hybrid-nsg-agent-blueprint-<region>-apim`) would
silently retag a same-named resource a customer created outside the blueprint if that name already
exists. A template-internal name comparison cannot close this gap: when no existing-resource ID is
supplied Bicep has no way to discover a same-named customer resource, and when one is supplied the
create branch is already disabled. The ownership boundary is therefore enforced in two distinct
places, neither of which pretends to detect collisions from inside the create branch:

1. **In-template input consistency (not collision detection).** Each conditional create-or-reference
   path keeps tags on the create branch only, and additionally calls `fail()` when the caller's
   inputs are self-contradictory: an existing-resource ID or reuse parameter resolves to a name
   that is also the deterministic name of a resource another input still forces the same
   deployment to create. The concrete brownfield cases are `existingApimNsgId` or
   `existingComputeNsgId` pointing at the matching deterministic per-purpose NSG while
   `reuseExistingNsgs` is `false`; that NSG would otherwise be created and tagged over the
   resource the caller declared as external. `sharedHybridNsgId` is not contradictory: its
   non-empty value sets `useSharedHybridNsg` and suppresses the NSG module regardless of
   `reuseExistingNsgs`. The equivalent existing-ID parameters for Storage, AI Search, Cosmos DB,
   and DNS use the same rule. This rejects contradictory ownership declarations deterministically;
   it makes no claim about undeclared resources.
2. **Out-of-template ownership preflight (the proof of ownership).** Creation with tags is not
   permitted without evidence that each deterministic blueprint-owned name is either absent or
   already blueprint-owned. This change adds `scripts/tags/preflight-owned-names.sh`, executed
   outside the templates before deployment, that consumes a deployment-specific manifest and
   queries Azure for each name it lists. The manifest is generated after the exact template,
   parameter, mode, optional-resource, and cross-scope choices have been resolved; it contains a
   schema version, Azure cloud, target deployment scope, template and effective-parameter digests,
   and one entry per planned tagged declaration with its logical name, resource type, subscription,
   resource group, name, and canonical resource ID. This makes the set of names and scopes
   deterministic rather than asking the script to rediscover them from loosely related arguments.

   The script writes a JSON evidence artifact containing its schema version, creation timestamp,
   manifest digest, and one result per manifest entry with the canonical resource ID and outcome
   (`absent` or `accepted-existing`). A name passes when it does not resolve to an existing
   resource, or when it resolves to a resource the operator has attested as blueprint-created by
   listing its canonical ID in `--accept-existing` and supplying that ID's prior evidence artifact
   with `--prior-evidence <path>`. That artifact must record the ID as `absent` for the same logical
   declaration and target scope. The script rejects malformed manifests or evidence, unknown or
   duplicate attestation IDs, manifest-digest/scope mismatches, and any unlisted existing resource
   with a non-zero exit. `OWNERSHIP_EVIDENCE_TTL_SECONDS=900` (15 minutes) is a hard-coded,
   non-overrideable evidence freshness invariant: the deployment gate accepts evidence only when
   its manifest digest matches the current manifest and its timestamp remains within that TTL of the
   ARM invocation; missing, stale, or mismatched evidence fails closed.
   On a first run, an existing name cannot be accepted because no prior evidence can record it as
   absent. A partially successful first deployment can be re-run only with the evidence artifact
   written by its successful preflight, which records the name as absent before that deployment
   created it. The gate's output is the required evidence artifact for the tagging deployment.

   Every deployment wrapper and documented direct deployment procedure must generate the manifest,
   run the preflight, and verify the fresh evidence immediately before invoking ARM. This applies
   to greenfield network (including private DNS and optional Bastion), brownfield network,
   brownfield DNS, Foundry, and Foundry DNS entry points. For Foundry, `scripts/foundry/deploy.sh`
   runs `scripts/foundry/preflight.sh` first and then
   `scripts/tags/deploy-with-ownership-preflight.sh` before ARM. A direct
   `az deployment group create` example must invoke the same gate with the exact template and
   effective parameters and must not present a bypass command as supported.

Ownership regression tests will cover both halves: a contradictory-input fixture asserting the
`fail()` path, and preflight fixtures asserting a non-zero exit and no emitted deployment for an
unattested existing resource, a missing/stale/mismatched evidence artifact, and a manifest that
omits a required scope or tagged declaration.

**Scope boundaries of this contract:**

- The preflight is an operator-run gate outside the ARM template, because Bicep cannot query
  resource existence during compilation or evaluation. Deployments that bypass the gate carry the
  full create-or-update retagging risk, which is why task 5.8 enforces it and task 6.2 documents it
  as a prerequisite rather than an optional check.
- The preflight is intentionally narrow: it checks only the deterministic names this change tags.
  The broader fail-closed network preflight validator in `specs/00-network-foundation/tasks.md`
  (T030-T033, T035-T039) still owns CIDR overlap and wider brownfield validation, and this change
  does not duplicate it.

This is preferred over deployment-level post-processing or generic tag-update resources, which
could cross ownership boundaries and mutate customer-managed infrastructure.

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
- greenfield and brownfield ownership modes emit only their owned resources;
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
- **[Risk] ARM create-or-update could retag a customer resource that happens to use a deterministic
  blueprint-owned name.** → Templates cannot detect this, so creation with tags is gated on an
  out-of-template ownership preflight that resolves every deterministic name, fails when a name
  resolves to an existing resource the operator has not attested as blueprint-created, and produces
  the required deployment evidence; in-template
  `fail()` covers only contradictory caller ownership inputs, and deployment guidance (task 6.2)
  documents the preflight as a prerequisite.
- **[Trade-off] Purpose-keyed maps are less discoverable than singular parameters.** → Publish the
  accepted logical keys and defaults in parameter contracts and customer examples.

## Migration Plan

1. Complete and review the resource ownership/tag-support inventory.
2. Add backward-compatible tag inputs to environment and module interfaces.
3. Preserve the Foundry shared `tags` input and layer resource-specific overrides over it.
4. Apply effective tags only to blueprint-created, taggable resources.
5. Update `.bicepparam` environment-variable contracts and sanitized examples.
6. Add compiled-template, parameter, merge-precedence, and ownership-boundary regression tests.
7. Update deployment documentation with supported and unsupported tag surfaces.
8. Run all offline builds and validation suites; record approval-dependent Foundry live gates as
   `BLOCKED`.

Rollback removes the new optional resource-specific inputs and assignments while retaining the
legacy Foundry shared tag contract and existing APIM behavior. Tags already applied in Azure may
remain until explicitly changed because tag rollback follows normal ARM update semantics.
