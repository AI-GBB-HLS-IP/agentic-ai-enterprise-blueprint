---

description: "Dependency-ordered implementation and validation tasks for Chapter 02"
---

# Tasks: APIM AI Gateway (Core Gateway)

**Input**: Design documents from `specs/02-apim-ai-gateway/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `quickstart.md`, and `contracts/apim-bicep-interface.md`

**Scope guard**: These tasks implement and validate only the private Premium v2 APIM core gateway. They must not create or modify the existing VNet, Foundry account/project/model deployment, `snet-privateendpoints`, or `privatelink.azure-api.net`, and must not add MCP, A2A, public fallback, Content Safety, semantic caching, or a secondary backend.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the APIM module and evidence paths without changing existing resources.

- [X] T001 Create the planned APIM module directory and POC composition paths at `infra/modules/apim/` and `infra/envs/poc/`, preserving the existing network and Foundry module files
- [X] T002 [P] Create the APIM validation evidence directory and command runner at `specs/02-apim-ai-gateway/validation/README.md` and `specs/02-apim-ai-gateway/validation/validate.sh`
- [X] T003 [P] Create the parameter contract for target resource names, existing resource IDs, Foundry deployment, APIM SKU/capacity, and observability names in `infra/envs/poc/apim.bicepparam`
- [X] T004 [P] Record the implementation-time API version, policy schema, and Log Analytics reuse decision in `specs/02-apim-ai-gateway/validation/api-confirmation.md`

## Phase 2: Foundational (Blocking Prerequisites and Research Gates)

**Purpose**: Confirm provider behavior and existing prerequisites before APIM or subnet changes are declared.

**CRITICAL**: No user story implementation may proceed until the prerequisite and provider gates in this phase are resolved or explicitly approved as manual gates.

- [X] T005 [P] Confirm the target `Microsoft.ApiManagement/service` API version, Premium v2/stv2 SKU syntax, internal VNet-injection schema, and private endpoint output properties with read-only Azure CLI/provider inspection, recording evidence in `specs/02-apim-ai-gateway/validation/api-confirmation.md`
- [ ] T006 [P] Confirm the current `llm-token-limit` and `llm-emit-token-metric` policy XML schema and supported APIM policy locations, recording the exact syntax and source in `specs/02-apim-ai-gateway/validation/api-confirmation.md`
- [X] T007 [P] Confirm whether Chapter 01 created a reusable Log Analytics workspace in `rg-agent-factory-poc` and record the selected workspace ID or create-new decision in `specs/02-apim-ai-gateway/validation/api-confirmation.md`
- [X] T008 [P] Validate that `rg-agent-factory-poc`, `vnet-agent-factory-poc`, `snet-apim`, the existing NSG association, `snet-privateendpoints`, `foundry-agent-factory-poc`, and `gpt-4.1-mini` exist with the expected region and address range in `specs/02-apim-ai-gateway/validation/validate.sh`
- [X] T009 [P] Confirm `snet-apim` is unused, has no conflicting delegation or resource claim, preserves its existing NSG association, and does not require unrelated NSG mutations; record results in `specs/02-apim-ai-gateway/validation/prerequisites.md`
- [X] T010 [P] Confirm `privatelink.azure-api.net` already exists or is absent without attempting to reuse it, and record the non-conflicting `azure-api.net` zone decision in `specs/02-apim-ai-gateway/validation/prerequisites.md`
- [ ] T011 Resolve all provider and prerequisite gates T005-T010, document remediation for failures, and block implementation/deployment in `specs/02-apim-ai-gateway/validation/README.md` while any mandatory gate remains unresolved
- [X] T012 Define shared parameter assertions, resource naming, existing-resource references, and readiness states (`existing`, `deployed`, `pending`, `failed`) in `infra/modules/apim/main.bicep` according to `contracts/apim-bicep-interface.md`

**Checkpoint**: Provider schema, policy syntax, workspace choice, subnet readiness, Foundry prerequisite, and DNS conflict checks are evidenced before any APIM resource is provisioned.

## Phase 3: User Story 1 - Deploy a Private, VNet-Injected AI Gateway (Priority: P1) 🎯 MVP

**Goal**: Delegate the existing APIM subnet and provision one Premium v2 APIM instance with internal VNet injection and no public gateway.

**Independent Test**: Run the resource-group what-if, inspect the deployed APIM SKU/network posture, and confirm `snet-apim` has the required delegation while its existing NSG association is preserved.

### Implementation for User Story 1

- [X] T013 [P] [US1] Implement the existing `snet-apim` subnet reference and `Microsoft.Web/serverFarms` delegation in `infra/modules/apim/subnet-delegation.bicep`, preserving the subnet address prefix and existing NSG association
- [X] T014 [P] [US1] Implement the Premium v2/stv2 APIM service with system-assigned identity, `virtualNetworkType: Internal`, and the confirmed `snet-apim` resource ID in `infra/modules/apim/main.bicep`
- [X] T015 [US1] Compose the subnet-delegation and APIM modules with location, publisher metadata, SKU/capacity, VNet/subnet IDs, and Foundry inputs in `infra/envs/poc/apim.bicep`, enforcing delegation-before-APIM dependency
- [X] T016 [US1] Add APIM service ID, gateway hostname, principal ID, subnet delegation status, VNet mode, subnet ID, and public-endpoint status outputs in `infra/modules/apim/main.bicep`
- [X] T017 [US1] Compile the subnet and APIM modules and run the resource-group what-if from `infra/envs/poc/apim.bicep` using `infra/envs/poc/apim.bicepparam`, saving the non-destructive preview to `specs/02-apim-ai-gateway/validation/us1-what-if.md`
- [ ] T018 [US1] Run the independent network-posture validation for delegation, NSG preservation, Premium v2 SKU, internal VNet injection, subnet placement, and absence of public gateway endpoints, recording results in `specs/02-apim-ai-gateway/validation/us1-gateway.md`

**Checkpoint**: US1 is complete only when the preview and inspection show the intended APIM/subnet changes and no public gateway path.

## Phase 4: User Story 2 - Connect APIM to Foundry with Managed Identity (Priority: P1)

**Goal**: Route APIM to the existing `gpt-4.1-mini` Foundry deployment using only APIM's system-assigned managed identity and private DNS.

**Independent Test**: Inspect the identity role scope and backend policy, resolve the APIM hostname from `vm-fnd-jbox`, and confirm no Foundry key, connection string, or secret is present in source, parameters, policies, or logs.

### Implementation for User Story 2

- [X] T019 [P] [US2] Implement the account-scoped `Cognitive Services OpenAI User` role assignment using APIM's principal ID and the exact Foundry account resource ID in `infra/modules/apim/main.bicep`
- [X] T020 [P] [US2] Implement the `azure-api.net` private DNS zone, VNet link, and post-provision APIM internal endpoint A records in `infra/modules/apim/private-dns.bicep`, keeping it distinct from `privatelink.azure-api.net` and ordering records after APIM IP publication
- [X] T021 [P] [US2] Implement the Foundry backend URL, `gpt-4.1-mini` deployment route, and `authentication-managed-identity` policy with audience `https://cognitiveservices.azure.com` in `infra/modules/apim/backend.bicep`
- [X] T022 [US2] Compose role assignment, DNS, and backend resources in `infra/envs/poc/apim.bicep` with explicit dependencies on the APIM identity, published private IPs, and existing Foundry account
- [X] T023 [US2] Add role assignment ID, DNS zone/link IDs, backend ID, and managed-identity readiness outputs in `infra/modules/apim/backend.bicep` and `infra/modules/apim/private-dns.bicep`
- [ ] T024 [US2] Validate account-only role scope, managed-identity policy content, absence of API keys/secrets, DNS zone separation, VNet link, and private hostname resolution from `vm-fnd-jbox`, recording evidence in `specs/02-apim-ai-gateway/validation/us2-identity-dns.md`

**Checkpoint**: US2 is ready only when identity authorization and private DNS pass; a missing role, public resolution, unresolved hostname, or secret reference fails readiness.

## Phase 5: User Story 3 - Expose One Governed Chat Completions API (Priority: P2)

**Goal**: Provide exactly one subscription-key-protected OpenAI-compatible `chat/completions` API with token controls, metrics, and APIM observability.

**Independent Test**: From a private VNet client, send ten valid non-streaming requests and one unauthenticated request; confirm at least nine valid requests reach `gpt-4.1-mini`, the unauthenticated request is rejected before Foundry, and token telemetry is attributable to the subscription without payloads or secrets.

### Implementation for User Story 3

- [X] T025 [P] [US3] Implement the single OpenAI-compatible `chat/completions` API, operation, Foundry backend binding, approved deployment routing, product, and subscription requirement in `infra/modules/apim/api.bicep`
- [X] T026 [P] [US3] Implement inbound subscription-key enforcement and the confirmed `llm-token-limit` policy keyed by `context.Subscription.Id` in `infra/modules/apim/api.bicep`
- [X] T027 [P] [US3] Implement outbound `llm-emit-token-metric` policy dimensions for subscription and API, rejecting unsupported model aliases or backend routes in `infra/modules/apim/api.bicep`
- [X] T028 [P] [US3] Implement Application Insights, selected/reused Log Analytics integration, APIM logger, and diagnostic settings that exclude request/response bodies, subscription keys, and sensitive headers in `infra/modules/apim/observability.bicep`
- [X] T029 [US3] Compose the API and observability modules in `infra/envs/poc/apim.bicep`, ensuring the only declared client-facing API is `chat/completions` and no MCP/A2A resource is introduced
- [X] T030 [US3] Add API, product/subscription, Application Insights, Log Analytics, logger, diagnostic, token-policy, and scope-boundary outputs in `infra/modules/apim/api.bicep` and `infra/modules/apim/observability.bicep`
- [X] T031 [US3] Compile every APIM module and run the APIM what-if after API/policy/observability composition, saving output and any provider limitations in `specs/02-apim-ai-gateway/validation/us3-what-if.md`
- [ ] T032 [US3] Execute the private ten-request success test and unauthenticated rejection test, confirm no corresponding Foundry call for rejected traffic, and record request/model evidence in `specs/02-apim-ai-gateway/validation/us3-requests.md`
- [ ] T033 [US3] Inspect APIM/Application Insights/Log Analytics telemetry for subscription-attributable token metrics and confirm request bodies, response bodies, keys, and sensitive headers are absent in `specs/02-apim-ai-gateway/validation/us3-observability.md`

**Checkpoint**: US3 is complete only when the one governed API meets the 9/10 success criterion, rejects 100% of unauthenticated requests before Foundry, emits token metrics, and contains no out-of-scope API.

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Prove idempotency, fail-closed behavior, traceability, and the complete quickstart workflow.

- [X] T034 [P] Add structured readiness aggregation for prerequisites, delegation, APIM, identity/role, DNS, backend, API, observability, and explicit MCP/A2A absence in `infra/modules/apim/main.bicep`
- [X] T035 [P] Extend `specs/02-apim-ai-gateway/validation/validate.sh` with fail-closed checks for public endpoints, broad role scope, DNS conflicts/public resolution, missing subscription enforcement, token metrics, sensitive logging, unsupported model routes, and MCP/A2A presence
- [X] T036 [P] Update `specs/02-apim-ai-gateway/quickstart.md` with implemented module paths, validation runner usage, evidence filenames, and the required deployment-approval gate
- [X] T037 [P] Document module inputs/outputs, ownership boundaries, no-secret invariant, and explicit out-of-scope MCP/A2A behavior in `specs/02-apim-ai-gateway/validation/README.md`
- [ ] T038 Run the unchanged-parameter APIM what-if a second time and compare it with the first preview to verify idempotency and absence of duplicate zones, links, role assignments, APIs, backends, policies, or diagnostics in `specs/02-apim-ai-gateway/validation/idempotency.md`
- [ ] T039 Run `az bicep build` for every changed APIM module, execute the full validation runner, and record final readiness, pending provider operations, and remediation hints in `specs/02-apim-ai-gateway/validation/final-report.md`

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 has no dependencies and establishes only paths and parameters.
- Phase 2 depends on Phase 1 and blocks all resource implementation until provider and prerequisite gates are resolved.
- Phase 3 depends on Phase 2 and is the MVP private gateway increment.
- Phase 4 depends on the APIM identity and private network posture from Phase 3; its module files can be developed in parallel after the API/schema gates pass.
- Phase 5 depends on the APIM service, managed identity authorization, backend, and DNS readiness from Phases 3-4.
- Phase 6 depends on the desired implementation and validation increments and must not expand the approved core-gateway boundary.

### User Story Dependencies

- **User Story 1 (P1)**: Starts after Phase 2; no dependency on API or backend configuration.
- **User Story 2 (P1)**: Requires the APIM resource and system-assigned identity from US1; role, DNS, and backend files can be developed in parallel after T011.
- **User Story 3 (P2)**: Requires successful US1 and US2 network/identity/backend gates before live request validation; API and observability files can be developed in parallel by file.

### Parallel Opportunities

- T002-T004 and T005-T010 can run in parallel because they touch separate paths or perform independent read-only checks.
- After T011, T013-T014 can proceed in parallel; T019-T021 can proceed in parallel once the APIM interface and provider gates are confirmed.
- T025-T028 can proceed in parallel because each task owns a separate APIM module file; T029-T033 remain composition and evidence steps.
- T034-T037 can proceed in parallel; T038-T039 are final verification tasks.

## Implementation Strategy

### MVP First

1. Complete Phase 1 and resolve every Phase 2 prerequisite/provider gate.
2. Implement and preview US1 only.
3. Validate subnet delegation, internal VNet injection, subnet placement, and no-public-endpoint posture.
4. Stop if the preview or network inspection fails; do not call the gateway an MVP until US1 passes.

### Incremental Delivery

1. Add US2 identity, backend, and private DNS resources and validate private resolution and account-scoped authorization.
2. Add US3's single API, policies, and observability, then run the private request and telemetry tests.
3. Finish readiness aggregation, idempotency, fail-closed checks, and final evidence.
4. Report APIM provisioning delays, provider approval requirements, or unresolved DNS/role state as incomplete rather than claiming deployment success.

## Notes

- Every task uses the required `- [ ] T###` checklist format; `[P]` is used only for independent work, and story tasks carry `[US1]`, `[US2]`, or `[US3]`.
- Every implementation or evidence task names an exact repository path.
- Live Azure commands must save their output to the named validation evidence file; compiling Bicep or producing a what-if does not itself prove deployment.
- Existing network, DNS, and Foundry resources are immutable prerequisites except for the explicitly required `snet-apim` delegation and documented Premium v2 network rules.
