## Why

The blueprint applies tags inconsistently outside the APIM foundation: some resources share one
Foundry tag object, while network, DNS, and optional platform resources expose no caller-controlled
tag contract. Enterprise deployments need explicit, auditable tag inputs for every taggable
blueprint-owned resource without applying tag inputs to dependencies referenced through
existing-resource or BYO paths. Ownership is declared by the operator, not discovered by this
tagging capability.

## What Changes

- Extend the archived APIM per-resource tagging pattern across blueprint-owned network, DNS,
  Foundry, supporting-service, private-endpoint, and optional Bastion resources.
- Expose independent tag objects with `{}` defaults so callers can configure resource-specific
  governance metadata without breaking existing parameter files.
- Preserve caller-provided Azure-valid tag keys and values without normalization, except for
  documented blueprint-controlled mandatory tags such as the APIM public IP `ProjectCode: APIM`.
- Apply tag inputs only on blueprint-managed create/update paths, including redeployment of
  previously blueprint-created resources; do not apply those inputs to resources referenced
  through existing-resource or BYO paths.
- Require operators to verify that every create/update target is absent or already blueprint-owned
  and prevent conflicting concurrent deployments. ARM can update a same-named unrelated resource;
  selecting a create path is not proof of ownership.
- Reject ownership-input contradictions determinable from the supplied inputs and active resource
  branches. Automatic collision discovery, ownership attestation, evidence gates, and concurrency
  enforcement are outside this capability and are not new deployment prerequisites.
- Inventory and document resources that do not support independent Azure resource tags, including
  role assignments and APIM or Foundry child and extension resources.
- Add parameter-contract, compiled-template, ownership-boundary, default-value, and regression
  validation using sanitized generic tag examples.
- Keep approval-dependent Foundry live validation explicitly `BLOCKED` until an authorized
  environment is available; offline tag propagation and declared-ownership checks remain mandatory.
- Treat the outstanding Stage 1 evidence-file reconciliation in
  `split-apim-foundry-deployment` as separate work that does not block this tagging capability.

## Capabilities

### New Capabilities

- `blueprint-resource-tagging`: Defines independent, backward-compatible Azure resource tag
  contracts and declared-ownership boundaries for taggable resources managed across the blueprint.

### Modified Capabilities

None.

## Impact

- Greenfield and brownfield environment entry points under `infra/envs/poc/`.
- Network, Foundry, DNS, supporting-resource, private-endpoint, and optional Bastion modules under
  `infra/modules/`.
- Existing APIM tagging interfaces, which remain compatible and retain their current mandatory
  public IP tag behavior.
- Environment-backed `.bicepparam` contracts and sanitized customer example parameter files.
- Network, Foundry, and APIM validation scripts and compiled-template regression tests.
- Deployment contracts, quickstarts, resource inventories, and validation evidence describing
  supported and unsupported tag surfaces.
- Tracking issue #81.
