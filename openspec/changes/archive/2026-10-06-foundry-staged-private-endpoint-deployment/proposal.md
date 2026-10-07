## Why

Live brownfield deployment surfaced a mismatch between how `infra/modules/foundry/main.bicep`
provisions Foundry and its dependent resources versus the approved, policy-driven staged
process. Per the approved reference ARM template and deployment guide: **Phase 2** is a single
ARM deployment that creates the Foundry account/project, any newly created dependent resources
(Storage, Cosmos DB, AI Search), bare private endpoints for all of them (with no private DNS zone
group attached yet), RBAC assignments, and the capability host — all together. **Phase 3** is a
separate, later step that associates each already-created private endpoint with its private DNS
zone group; the reference process performs this manually, per resource, via the Azure Portal.

So the actual required split is **not** "create the base resource, then create the private
endpoint" — private endpoints ARE created in the same deployment as the account. It is "create
everything including bare private endpoints in one deployment, then associate DNS zone groups
in a second, later step." Our current module conflates private-endpoint creation with DNS
zone-group association inside one `private-endpoint.bicep` module, which does not match that
required sequencing and risks the same kind of policy/timing failure already hit and fixed on the
network side (`brownfield-apim-network-policy-compliance`).

## What Changes

- Split `infra/modules/foundry/private-endpoint.bicep`'s private endpoint creation from its
  private DNS zone group creation: `private-endpoint.bicep` keeps creating bare private endpoints
  (Foundry account, Storage, Key Vault, Cosmos DB, AI Search) with no DNS association, and a new
  `private-endpoint-dns.bicep` module creates the `privateDnsZoneGroups` child resources against
  those already-existing private endpoints (referenced by full resource ID as `existing`).
- `infra/modules/foundry/main.bicep` keeps creating the account/project, dependent resources, and
  bare private endpoints together in one deployment (matching the approved Phase 2
  behavior) — it no longer accepts or threads through private DNS zone IDs.
- Add a new, separately deployable "DNS association" phase: `infra/envs/poc/foundry-dns.bicep`
  (module wrapper around `private-endpoint-dns.bicep`), deployable only after the main Foundry
  deployment's private endpoints exist, accepting their full resource IDs (including IDs for
  independently supplied private endpoints) as inputs — the Bicep equivalent of the approved
  manual per-resource Portal step, matching the
  existing `brownfield-network.bicep` + `brownfield-dns.bicep` precedent for the same class of
  problem.
- Both phases remain idempotent and safe to re-run individually.
- Reuse the existing `TEMPLATE_FILE`/`PARAMETER_FILE` overrides in
  `scripts/foundry/deploy.sh` and `scripts/foundry/what-if.sh` to invoke each deployment phase
  separately. `scripts/foundry/preflight.sh` remains the shared prerequisite check and does not
  consume those template/parameter overrides.
- Document the two-phase requirement and the reasoning behind it (the approved reference ARM
  template creates private endpoints without DNS association; DNS zone group attachment is a
  distinct, later step) in the Foundry deployment guide.
- **BREAKING**: `infra/modules/foundry/main.bicep` no longer accepts `privateDnsZoneIds`, and
  `infra/envs/poc/foundry.bicep` no longer resolves or wires private DNS zones — callers must run
  the new `foundry-dns.bicep` deployment afterward to attach DNS zone groups; a foundry deployment
  without that second step leaves private endpoints created but not DNS-associated (matching the
  approved Phase 2/Phase 3 split, but now both phases are templated instead of the DNS phase
  being manual).

## Capabilities

### New Capabilities
(none — this modifies the existing Foundry BYO networking capability's deployment sequencing
requirement; no new capability domain is introduced)

### Modified Capabilities
- `01-foundry-byo-networking`: FR-006/FR-006a are revised so the main deployment creates the
  Foundry resources and bare private endpoints together, while a distinct later DNS-association
  deployment accepts full private-endpoint resource IDs.

## Impact

- `infra/modules/foundry/private-endpoint.bicep` (drop DNS zone group resources/params, add PE
  resource-ID outputs), new `infra/modules/foundry/private-endpoint-dns.bicep`.
- `infra/modules/foundry/main.bicep` (drop `privateDnsZoneIds` threading, add PE resource-ID
  outputs).
- `infra/envs/poc/foundry.bicep` (drop DNS zone resolution), new `infra/envs/poc/foundry-dns.bicep`
  + `foundry-dns.bicepparam.example`.
- `scripts/foundry/deploy.sh` and `what-if.sh` (existing template/parameter overrides are used
  once per phase); `preflight.sh` remains the unchanged shared prerequisite check.
- `docs/` — Foundry deployment guide (new or existing doc covering `infra/envs/poc/foundry.bicep`).
- `specs/01-foundry-byo-networking/spec.md` (FR-006 delta).
- No change to the network module or the already-implemented
  `brownfield-apim-network-policy-compliance` work.
