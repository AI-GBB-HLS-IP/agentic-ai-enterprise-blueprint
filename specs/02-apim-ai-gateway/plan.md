# Implementation Plan: APIM AI Gateway (Core Gateway)

**Branch**: `spec/02-apim-ai-gateway` | **Date**: 2026-08-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/02-apim-ai-gateway/spec.md`

## Summary

Implement a resource-group-scoped, parameterized Bicep module family that deploys a private,
internal-VNet-injected Azure API Management classic Premium instance into the existing dedicated
`snet-apim` subnet, and connects it to the existing Chapter 01 Foundry
deployment using APIM's system-assigned managed identity — no Foundry API keys or backend secrets. The feature
exposes exactly one client-facing, subscription-key-protected, OpenAI-compatible
`chat/completions` API routed to the approved `gpt-4.1-mini` deployment, with token rate
limiting, token metrics, and Application Insights/Log Analytics observability. MCP server
publication and A2A agent routing remain out of scope and are deferred to later increments.

## Technical Context

**Language/Version**: Bicep (repository-supported CLI/provider API versions; confirm APIM
`Microsoft.ApiManagement/service` API version supporting classic Premium internal VNet injection)

**Primary Dependencies**: Azure Resource Manager; `Microsoft.ApiManagement`,
`Microsoft.Network` (subnets, private DNS, NSGs), `Microsoft.Authorization` (role assignments),
`Microsoft.Insights`/Log Analytics resource providers; Azure CLI/Bicep CLI

**Storage**: N/A — this feature adds no new data stores; it reuses the existing Chapter 01
Storage/Key Vault only indirectly through Foundry

**Testing**: `az bicep build`, `az deployment group what-if`, Azure CLI validation, private DNS
resolution checks from `vm-fnd-jbox`, subscription-key-authenticated and unauthenticated
`chat/completions` request tests, token metric inspection

**Target Platform**: Single-region Azure POC subscription, resource-group deployment in
`rg-agent-factory-poc` (`eastus2`)

**Project Type**: Infrastructure-as-code modules and validation documentation

**Performance Goals**: Deployment (excluding APIM Premium provisioning time, which commonly
exceeds 45 minutes) validated end-to-end; at least 9/10 consecutive private `chat/completions`
requests succeed

**Constraints**: Existing VNet/subnets/Foundry deployment are immutable prerequisites except for
the explicitly-required `snet-apim` delegation; no public gateway endpoint; no API keys for
backend auth; MCP/A2A explicitly out of scope; fail closed on unauthenticated requests

**Scale/Scope**: One APIM instance, one Foundry backend, one client-facing API, one model
deployment (`gpt-4.1-mini`); no multi-model backend pool, no semantic cache, no Content Safety
resource in this increment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Separation of duties:** PASS. Platform Engineering owns the APIM/network Bicep and subnet
  delegation; AI CoE governs which model(s)/policies are approved (already approved
  `gpt-4.1-mini` in Chapter 01); developers only ever receive a subscription key, never
  infrastructure access.
- **Spec before infra:** PASS. This plan follows `spec.md`; no Bicep exists yet in
  `infra/modules/apim/` and none will be generated until this plan and `tasks.md` are complete
  and the deployment is explicitly approved.
- **Private by default/no bypass:** PASS. No public gateway endpoint; all backend auth is
  managed-identity based; Content Safety inherits from Foundry (out of scope to disable here);
  the client-facing API enforces subscription-key auth as the sole entry chokepoint.
- **Incremental/testable slices:** PASS. Gateway deployment, identity/role wiring, DNS
  resolution, and the client-facing API each have an independent test in `spec.md` (User
  Stories 1-3).
- **IaC/validation:** PASS. Design uses parameterized Bicep, existing-resource references,
  `az bicep build`, and `what-if`; regional APIM capacity cannot be confirmed via the quota API,
  so `what-if` is treated as a mandatory pre-deployment gate rather than a formality.
- **Gate status:** PASS before research; to be re-evaluated after Phase 1 design.

## Project Structure

### Documentation (this feature)

```text
specs/02-apim-ai-gateway/
├── spec.md               # Feature specification (merged)
├── plan.md               # This file
├── research.md           # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   └── apim-bicep-interface.md
└── tasks.md              # Phase 2 output (/speckit.tasks — not created by this plan)
```

### Source layout

```text
infra/
├── envs/poc/
│   ├── main.bicep                 # existing network environment composition
│   ├── foundry.bicep              # existing Foundry environment composition
│   ├── apim.bicep                 # NEW: APIM environment composition
│   └── apim.bicepparam            # NEW: APIM environment parameters
└── modules/apim/
    ├── main.bicep                 # APIM service, VNet injection, managed identity
    ├── private-dns.bicep          # azure-api.net zone, VNet link, endpoint records
    ├── backend.bicep              # Foundry backend + managed-identity auth policy
    ├── api.bicep                  # client-facing chat/completions API + policies
    └── observability.bicep        # Application Insights, Log Analytics, logger, diagnostics
```

**Structure Decision**: Add a focused `infra/modules/apim/` module family and a POC parameter
file, mirroring the Chapter 01 `infra/modules/foundry/` pattern. Reference existing network and
Foundry resources by ID/name; do not alter `infra/modules/network/` module internals beyond
composing the new subnet-delegation module against the existing `snet-apim` resource, and do not
alter `infra/modules/foundry/` at all.

## Resource and module design

1. **Environment composition (`infra/envs/poc/apim.bicep`):** pass location, existing VNet/subnet
   IDs, existing Foundry account ID and model deployment name, and APIM SKU/capacity parameters.
2. **APIM subnet:** validate that the dedicated `snet-apim` subnet meets classic Premium
   injection requirements and preserve its existing NSG association; do not add v2 delegation.
3. **APIM service module:** create the classic Premium instance with `virtualNetworkType: Internal`,
   system-assigned managed identity enabled, and no public IP/gateway.
4. **Private DNS module:** create the new `azure-api.net` zone (distinct from the existing
   `privatelink.azure-api.net` zone), link it to `vnet-agent-factory-poc`, and create A records
   for the APIM internal endpoint(s) only after the APIM resource publishes its private IP.
5. **Role assignment:** grant the APIM managed identity `Cognitive Services OpenAI User`
   (`5e0bd9bd-7b93-4f28-af87-19fc36ad61bd`) scoped only to the `foundry-agent-factory-poc`
   account.
6. **Backend module:** define the Foundry backend using `authentication-managed-identity` with
   audience `https://cognitiveservices.azure.com`; no key vault reference, no named value
   secret.
7. **API module:** define the client-facing `chat/completions` API/product with subscription-key
   enforcement, `llm-token-limit`, and `llm-emit-token-metric` policies.
8. **Observability module:** create Application Insights, a Log Analytics workspace (or reuse
   Chapter 01's if one exists — confirm during research), an APIM logger, and a diagnostic
   setting that excludes secrets/request bodies.
9. **Validation module/script contract:** report subnet delegation/NSG state, APIM
   provisioning state and VNet injection mode, identity/role correctness, DNS zone/record/
   resolution state, and request test outcomes (authorized success, unauthorized rejection).

Dependency order is: confirm `snet-apim` is still unused → deploy APIM
(VNet-injected) → enable managed identity → assign Foundry role → create `azure-api.net` zone
and link → create DNS records once APIM publishes its private IP → configure backend → configure
client-facing API/policies → configure observability → run private request tests. VNet injection
is configured at creation time and must be validated before deployment.

## Validation and quota strategy

- Compile every Bicep module and run resource-group `what-if`; attach output to the PR, since
  regional APIM capacity cannot be confirmed through the quota API.
- Confirm `snet-apim` has no conflicting resource and meets classic Premium subnet requirements.
- Verify the APIM resource has no public gateway endpoint enabled and its VNet injection type is
  `Internal`.
- Verify the managed identity's role assignment is scoped only to the Foundry account, not the
  resource group or subscription.
- Resolve the APIM internal endpoint hostname from a VNet host (`vm-fnd-jbox`) and confirm a
  private `10.0.1.x` address.
- Send ten consecutive non-streaming `chat/completions` requests with a valid subscription key
  and confirm at least nine succeed and are attributable to `gpt-4.1-mini`; send one request
  without a key and confirm APIM rejects it before it reaches Foundry.
- Confirm no MCP server or A2A agent API exists after deployment, to keep this increment's
  boundary auditable against later Chapter 02 work.

## Research questions and risks

See [research.md](research.md) for sources and decisions. Implementation must confirm: the exact
`Microsoft.ApiManagement/service` API version and Bicep schema for classic Premium internal VNet
injection; whether an existing Log Analytics workspace from Chapter 01
should be reused or a new one created; the exact `llm-token-limit`/`llm-emit-token-metric` policy
XML schema for the current API version; and whether APIM Premium v2 provisioning time (often
45+ minutes) affects the validation workflow's expected duration.

## Phase 0: Research

Documented in [research.md](research.md): resolves the classic Premium VNet-injection/subnet
model and records Premium v2 as the preferred future tier, the
private DNS zone naming decision, and the managed-identity backend authentication pattern.

## Phase 1: Design artifacts

- [data-model.md](data-model.md) defines prerequisites, managed entities (APIM instance,
  managed identity/role assignment, Foundry backend, private DNS zone, client-facing API,
  observability stack), and readiness transitions.
- [contracts/apim-bicep-interface.md](contracts/apim-bicep-interface.md) defines planned module
  inputs, outputs, and fail-closed invariants (no public endpoint, no API key, subscription
  enforced).
- [quickstart.md](quickstart.md) defines runnable preview, delegation, connectivity, DNS, and
  request-test validation scenarios.

## Complexity Tracking

No constitution violations. The module split (subnet delegation, APIM service, private DNS,
role assignment, backend, client-facing API, observability) mirrors the Chapter 01 module
granularity and keeps each piece independently testable without altering the existing network
foundation or Foundry modules.
