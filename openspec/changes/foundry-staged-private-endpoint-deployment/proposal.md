## Why

Live brownfield deployment against a real customer tenant surfaced a mismatch between how
`infra/modules/foundry/main.bicep` provisions Foundry and its dependent resources versus a
documented, policy-driven staged process required by that tenant: the base PaaS resource
(Foundry account/project, and by extension Storage, Cosmos DB, AI Search, and Key Vault) must be
fully created first with its private-endpoint configuration left blank, and only afterward is the
private endpoint (plus its private DNS zone group) created as a separate, subsequent deployment.
Our current module wires the account and its private endpoints together in one combined
deployment, which does not match that required sequencing and risks the same kind of
policy/timing failure already hit and fixed on the network side
(`brownfield-apim-network-policy-compliance`).

## What Changes

- Split `infra/modules/foundry/main.bicep`'s single combined deployment into two independently
  deployable phases: a "base resources" phase (Foundry account/project and any newly created
  dependent resources: storage, Cosmos DB, AI Search — all with public network access disabled,
  no private endpoints attached) and a "private endpoint" phase (creates the private endpoints
  and private DNS zone groups for all resources created or referenced in phase 1).
- The private-endpoint phase MUST be deployable only after phase 1 has succeeded, and MUST accept
  the resource IDs produced by phase 1 (or BYO resource IDs) as inputs rather than assuming they
  are being created in the same deployment.
- Both phases remain idempotent and safe to re-run individually, consistent with existing
  brownfield conventions (see `docs/deploy-00-network.md` for the precedent of splitting network
  and DNS into separate deployable templates).
- Update `infra/envs/poc/foundry.bicep`/`foundry.bicepparam.example` and
  `scripts/foundry/deploy.sh` to drive the two phases as sequential, separately invokable steps
  (not a hidden internal detail of a single template).
- Document the two-phase requirement and the reasoning behind it (some tenant policies expect the
  base resource to exist before a private endpoint is attached) in the Foundry deployment guide.
- **BREAKING**: existing single-phase `foundry.bicep` callers must switch to invoking the base
  phase then the private-endpoint phase as two separate deployments; a single `az deployment group
  create` against the old combined template will no longer be the documented path.

## Capabilities

### New Capabilities
(none — this modifies the existing Foundry BYO networking capability's deployment sequencing
requirement; no new capability domain is introduced)

### Modified Capabilities
- `01-foundry-byo-networking`: FR-006 (private endpoint creation) is revised to require the
  private endpoints for Foundry and its dependent resources to be deployable as a distinct,
  subsequent step after the base resources exist, rather than as part of the same deployment
  operation that creates those base resources.

## Impact

- `infra/modules/foundry/main.bicep`, `private-endpoint.bicep`, `storage.bicep`, `ai-search.bicep`,
  `cosmos-db.bicep` (need to be restructured/split across the two phases).
- `infra/envs/poc/foundry.bicep`, `foundry.bicepparam.example`.
- `scripts/foundry/deploy.sh`, `preflight.sh`, `what-if.sh`.
- `docs/` — Foundry deployment guide (new or existing doc covering `infra/envs/poc/foundry.bicep`).
- `specs/01-foundry-byo-networking/spec.md` (FR-006 delta).
- No change to the network module or the already-implemented
  `brownfield-apim-network-policy-compliance` work.
