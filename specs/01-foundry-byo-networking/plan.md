# Implementation Plan: Microsoft Foundry with BYO Networking

**Branch**: `spec/01-foundry-byo-networking` | **Date**: 2026-08-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/01-foundry-byo-networking/spec.md`

## Summary

Design a resource-group-scoped, parameterized Bicep implementation that consumes the existing
network foundation and creates a private Microsoft Foundry account/project, required Storage
and Key Vault (optional SQL), private endpoints/DNS zone groups, create-time BYO VNet/network
injection, and one explicitly approved model deployment. This phase stops at design artifacts;
it does not implement infrastructure code.

## Technical Context

**Language/Version**: Bicep (repository-supported CLI/provider API versions; confirm Foundry API version during implementation)

**Primary Dependencies**: Azure Resource Manager; Microsoft.CognitiveServices, Microsoft.Network, Microsoft.Storage, Microsoft.KeyVault, optional SQL resource providers; Azure CLI/Bicep CLI

**Storage**: Azure Storage account (required); Key Vault (required); Azure SQL conditional on workload

**Testing**: `az bicep build`, `az deployment group what-if`, Azure CLI validation, private-host DNS checks, private endpoint state checks, model smoke test

**Target Platform**: Single-region Azure POC subscription, resource-group deployment in `rg-agent-factory-poc`

**Project Type**: Infrastructure-as-code modules and validation documentation

**Performance Goals**: Deployment under 30 minutes excluding quota/provider approval; 9/10 successful private smoke tests

**Constraints**: Existing VNet/subnets/zones are immutable prerequisites; no public endpoints or fallback; BYO VNet before agents; same region/resource group; fail closed on unhealthy PE/DNS/quota

**Scale/Scope**: One Foundry account/project, one approved model, one POC region; SQL conditional; no agents/APIM/multi-region

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Separation of duties:** PASS. Platform Engineering owns Bicep/networking; AI CoE supplies model approval; developers receive no infrastructure administration.
- **Spec before infra:** PASS. This plan follows `spec.md`; no `infra/` implementation is created in this phase.
- **Private by default/no bypass:** PASS. Public network access is disabled and validation fails closed; no public fallback is designed.
- **Incremental/testable slices:** PASS. Foundation, private connectivity, and one model smoke test are independently verifiable.
- **IaC/validation:** PASS. Design uses parameterized Bicep, existing-resource references, `az bicep build`, and `what-if`.
- **Gate status:** PASS before research; PASS after design, with API confirmations listed as implementation prerequisites rather than hidden assumptions.

## Project Structure

### Documentation

```text
specs/01-foundry-byo-networking/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/foundry-bicep-interface.md
```

### Planned source layout

```text
infra/
├── envs/poc/
│   ├── main.bicep                 # existing environment composition; integrate later
│   └── foundry.bicepparam         # planned environment parameters
└── modules/foundry/
    ├── main.bicep                 # planned account/project orchestration
    ├── supporting-resources.bicep
    ├── private-endpoint.bicep
    ├── model-deployment.bicep
    └── validation.bicep            # planned assertions/outputs
```

**Structure Decision**: Add a focused `infra/modules/foundry/` module family and a POC
parameter file. Reference existing network resources by ID/name and keep network foundation
ownership in `infra/modules/network/`; do not alter those modules in this feature.

## Resource and module design

1. **Environment composition:** pass location, existing resource IDs, DNS zone IDs/names,
   workload flags, and AI CoE-approved model parameters from `infra/envs/poc`.
2. **Foundry account/project module:** create the account with deny-by-default ACLs, disabled
   public access, and create-time network injection/BYO VNet properties if confirmed by the
   provider API; then create the project.
3. **Supporting-resources module:** create private Storage and Key Vault, conditionally SQL,
   with managed identity/RBAC inputs documented separately. Keep all in the same RG/region.
4. **Private-endpoint module:** create account/dependency endpoints in `snet-privateendpoints`,
   use live-confirmed group IDs, and attach DNS zone groups to existing zones. Do not create
   zones or public IPs.
5. **Model module:** after quota/model preflight, create exactly one account deployment with
   explicit model metadata, SKU/serving option, and capacity.
6. **Validation module/script contract:** report prerequisite versus managed-resource status,
   subnet delegation/ranges/utilization, placement, public access, PE approval, DNS links and
   resolution, model metadata/quota, and private smoke-test readiness.

Dependency order is: existing foundation/DNS validation → account with BYO settings →
project → supporting resources → private endpoints and DNS groups → PE approval/DNS checks →
quota preflight → model deployment → smoke test/readiness report. Project-before-PE is a
provider-behavior safeguard and must be revisited if the confirmed API documents another order.

## Validation and quota strategy

- Compile every Bicep module and run resource-group `what-if`; attach output to the PR.
- Validate exact subnet names/prefixes/delegation and fail if utilization is >=80%.
- Query `privateLinkResources` for group IDs/zones and verify all PE connections are `Approved`.
- Verify no public IP resources are introduced and account/dependency public access is disabled.
- Resolve private FQDNs from a VNet host and run the approved model through the private endpoint.
- Run live regional model availability/quota checks before enabling the model module. Capacity
  is a parameter, not a guarantee; stop on quota failure and never select an alternate model.

## Research questions and risks

See [research.md](research.md) for sources and decisions. Implementation must confirm:
`networkInjections` schema/API version, exact private-link group IDs and DNS zones, conditional
SQL requirements and Foundry references, PE approval behavior, authoritative subnet utilization
signal, and whether model quota is regional or subscription-shared. If any create-time BYO
capability cannot be represented in supported ARM/Bicep, stop and document the smallest
governed deployment-time/manual gate rather than claiming full IaC support.

## Phase 0: Research

Completed in [research.md](research.md). It resolves choices known from current templates and
records provider capabilities requiring live confirmation.

## Phase 1: Design artifacts

- [data-model.md](data-model.md) defines prerequisites, managed entities, relationships, and
  readiness transitions.
- [contracts/foundry-bicep-interface.md](contracts/foundry-bicep-interface.md) defines planned
  module inputs, outputs, and fail-closed invariants.
- [quickstart.md](quickstart.md) defines runnable preview, connectivity, DNS, quota, and smoke
  test validation scenarios.

## Complexity Tracking

No constitution violations. The module split is limited to account/project, supporting
resources, private endpoints, model deployment, and validation to preserve testable boundaries
without changing the existing network foundation.
