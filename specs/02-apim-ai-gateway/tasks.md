# Chapter 02 Delivery Checklist

The implementation source of truth is
`openspec/changes/split-apim-foundry-deployment/tasks.md`. This checklist presents the same work
in operator order and must not be used to claim live evidence that has not been collected.

## Stage 1 — APIM Foundation

### Prerequisites

- [ ] Record the target APIM resource group and approved region.
- [ ] Record the existing VNet and APIM subnet.
- [ ] Confirm `apimsubnet-*` naming or attach the approved naming-exception reference.
- [ ] Confirm the approved NSG association.
- [ ] Confirm the approved APIM route table, or attach the active tenant-policy exception.
- [ ] Confirm no subnet delegation and all four required service endpoints.
- [ ] Confirm the approved Standard static APIM public IP.
- [ ] Confirm the corporate publisher email and diagnostics ownership mode.

### Implementation

- [x] Separate APIM foundation and Foundry integration contracts.
- [ ] Make `infra/modules/apim/main.bicep` APIM-only.
- [ ] Make `infra/envs/poc/apim.bicep` compose only APIM, DNS, and observability.
- [ ] Reduce `apim.bicepparam` to foundation inputs.
- [ ] Add customer security, diagnostics, and capacity-monitoring controls.
- [ ] Add foundation-only validation and regression checks.

### Commands and Checkpoint

```bash
specs/02-apim-ai-gateway/validation/validate.sh foundation
az deployment group what-if --resource-group <apim-rg> \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam
```

- [ ] Save preview evidence to `validation/foundation-preview.md`.
- [ ] Deploy or inspect Stage 1 in an authorized environment.
- [ ] Save runtime evidence to `validation/foundation-runtime.md`.
- [ ] Confirm `foundationReadiness=deployed` and `integrationReadiness=not-deployed`.

Stage 1 is complete without any Foundry account, deployment, role, or API.

## Stage 2 — Foundry Integration

### Prerequisites

- [ ] Confirm Stage 1 readiness.
- [ ] Record GenAI Review Board approval and Foundry enablement references.
- [ ] Confirm the account is in an allowed customer region.
- [ ] Confirm Foundry public network access is disabled and private connectivity is approved.
- [ ] Confirm every mapped model is customer-approved and deployed.
- [ ] Confirm permission to create the account-scoped role assignment.

### Implementation

- [ ] Add the integration Bicep entry point and parameter file.
- [ ] Reference APIM as existing and derive its principal ID.
- [ ] Compose the Foundry role, backend, model mapping, API, product, and policies.
- [ ] Add integration-only validation and regression checks.

### Commands and Checkpoint

```bash
specs/02-apim-ai-gateway/validation/validate.sh integration
az deployment group what-if --resource-group <apim-rg> \
  --template-file infra/envs/poc/apim-foundry-integration.bicep \
  --parameters infra/envs/poc/apim-foundry-integration.bicepparam
```

- [ ] Save preview evidence to `validation/integration-preview.md`.
- [ ] Deploy or inspect Stage 2 in an authorized environment.
- [ ] Save request and telemetry evidence to `validation/integration-runtime.md`.
- [ ] Confirm foundation resources are unchanged and `integrationReadiness=deployed`.

## Aggregate and Handoff

- [ ] Run `validate.sh all` where both stages and approvals are available.
- [ ] Re-run each preview unchanged and record stage-specific idempotency.
- [ ] Update `validation/final-report.md` with separate readiness states.
- [ ] Update #71 and link the implementation pull request.
