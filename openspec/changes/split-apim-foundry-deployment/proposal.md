## Why

Chapter 02 currently treats the Chapter 01 Foundry deployment as a prerequisite for the entire
APIM deployment, even though APIM and its supporting network, identity, DNS, and monitoring
resources can be provisioned independently. Separating the deployment lets platform teams build
and validate the gateway foundation while Foundry approval or model availability is still pending.

## What Changes

- Split Chapter 02 into two explicit, independently deployable stages:
  - **APIM foundation** deploys networking prerequisites, internal VNet-injected APIM, its
    system-assigned identity, private DNS, and monitoring without reading or validating Foundry
    resources.
  - **Foundry integration** runs only after Foundry is approved and available, adding the
    Foundry-scoped role assignment, managed-identity backend, model mapping, and governed AI API.
- Replace the chapter-wide Foundry prerequisite with stage-specific prerequisites and validation
  gates.
- Refactor Chapter 02 infrastructure parameters and modules so the foundation deployment has no
  required Foundry resource ID, endpoint, or model deployment input.
- Separate validation evidence for foundation readiness from end-to-end Foundry-backed API
  validation.
- Preserve idempotent staged deployment so Foundry integration can be added later without
  replacing or disrupting the APIM foundation.

## Capabilities

### New Capabilities

- `staged-apim-deployment`: Defines the independent APIM foundation and deferred Foundry
  integration stages, including their inputs, outputs, ordering, and validation boundaries.

### Modified Capabilities

None. The repository has no existing OpenSpec capability specifications; the current Chapter 02
requirements live in legacy feature-spec artifacts that implementation will revise.

## Impact

- Affects `chapters/02-ai-gateway.md` and the Chapter 02 specification, plan, task, quickstart, and
  validation documentation under `specs/02-apim-ai-gateway/`.
- Affects Chapter 02 Bicep entry points, modules, parameters, outputs, deployment scripts, and
  validation scripts that currently assume Foundry exists.
- Changes deployment sequencing and operator guidance, but does not change the intended APIM SKU,
  internal networking posture, managed-identity authentication, DNS model, or observability goals.
- Tracks implementation in GitHub issue #71 on branch
  `spec/02-split-apim-foundry-deployment`.
