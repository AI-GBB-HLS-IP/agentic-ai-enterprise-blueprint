---

description: "Dependency-ordered implementation and validation tasks for Chapter 01"
---

# Tasks: Microsoft Foundry with BYO Networking

**Input**: Design documents from `specs/01-foundry-byo-networking/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `quickstart.md`, and `contracts/foundry-bicep-interface.md`

**Scope guard**: These tasks create and validate implementation artifacts; completion of this list must not be reported as a live deployment unless the validation tasks have been run against the target subscription.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the implementation and evidence structure without changing the existing network foundation.

- [ ] T001 Create the planned Foundry module and POC environment paths in `infra/modules/foundry/` and `infra/envs/poc/` without modifying `infra/modules/network/`
- [ ] T002 [P] Record target subscription, resource group, region, resource names, and existing network/DNS resource IDs in `infra/envs/poc/foundry.bicepparam`
- [X] T003 [P] Create the Chapter 01 validation evidence directory and command runner at `specs/01-foundry-byo-networking/validation/README.md` and `specs/01-foundry-byo-networking/validation/validate.sh`
- [X] T004 [P] Create the model approval and quota evidence template at `specs/01-foundry-byo-networking/validation/model-approval.md`, including model name, version, format, SKU, capacity, approver, and timestamp

## Phase 2: Foundational (Blocking Prerequisites and Research Gates)

**Purpose**: Confirm current provider behavior and existing prerequisites before any deployment code is written.

- [ ] T005 [P] Confirm the supported Microsoft Foundry account/project API version and `networkInjections`/BYO VNet schema in the target subscription, recording CLI/API responses and source links in `specs/01-foundry-byo-networking/validation/api-confirmation.md`
- [ ] T006 [P] Query target Foundry and dependency `privateLinkResources` to confirm private-link group IDs and authoritative DNS zones, recording results in `specs/01-foundry-byo-networking/validation/api-confirmation.md`
- [ ] T007 [P] Confirm whether the selected workload requires SQL and whether account properties must reference Storage, Key Vault, SQL, or managed identities; record the decision in `specs/01-foundry-byo-networking/validation/api-confirmation.md`
- [ ] T008 [P] Confirm private endpoint approval behavior and the authoritative delegated-subnet utilization signal, including the >=80% blocking rule, in `specs/01-foundry-byo-networking/validation/api-confirmation.md`
- [ ] T009 [P] Confirm live regional model availability and quota scope for the AI CoE-approved model, and populate `specs/01-foundry-byo-networking/validation/model-approval.md`
- [X] T010 Validate the existing resource group, VNet, `snet-foundry` delegation/range, `snet-privateendpoints` range, and required private DNS zones/links with a fail-closed prerequisite check in `specs/01-foundry-byo-networking/validation/validate.sh`
- [ ] T011 Resolve all research gates T005-T009 and document any unsupported create-time BYO VNet capability and its approved manual gate in `specs/01-foundry-byo-networking/validation/api-confirmation.md`; do not proceed to Bicep implementation while a gate is unresolved
- [ ] T012 Define shared fail-closed parameter assertions and status values (`existing`, `deployed`, `pending`, `failed`) in `infra/modules/foundry/main.bicep` only after T011 is approved

**Checkpoint**: Research, network prerequisites, quota evidence, and the implementation path are approved; no account, endpoint, or model deployment code should be applied before this checkpoint.

## Phase 3: User Story 1 - Provision a Private Foundry Foundation (Priority: P1) 🎯 MVP

**Goal**: Provision one same-region Foundry account/project plus required private supporting resources while consuming the existing foundation.

**Independent Test**: Run the resource-group what-if and inspect the resulting inventory/configuration to confirm only declared Chapter 01 resources are affected, Foundry is private by default, and Storage/Key Vault are present (SQL only when enabled).

### Implementation for User Story 1

- [ ] T013 [P] [US1] Implement Foundry account creation with `AIServices`, approved API version, disabled public access, deny-by-default ACLs, and confirmed create-time BYO VNet properties in `infra/modules/foundry/main.bicep`
- [ ] T014 [P] [US1] Implement same-region private Storage and Key Vault resources with public access disabled, required identity/configuration inputs, and explicit `enableSql` branching in `infra/modules/foundry/supporting-resources.bicep`
- [ ] T015 [US1] Implement Foundry project creation as a child of the account in `infra/modules/foundry/main.bicep`, preserving account-before-project ordering
- [ ] T016 [US1] Compose `location`, existing resource IDs, DNS inputs, workload flags, and account/project/supporting-resource outputs in `infra/envs/poc/main.bicep`
- [ ] T017 [US1] Add all required interface parameters and outputs, including account/project/supporting-resource IDs and declared status fields, to `infra/modules/foundry/main.bicep` according to `specs/01-foundry-byo-networking/contracts/foundry-bicep-interface.md`
- [ ] T018 [US1] Build the Foundry modules and run `az deployment group what-if` using `infra/envs/poc/foundry.bicepparam`, saving preview evidence to `specs/01-foundry-byo-networking/validation/us1-what-if.md`
- [ ] T019 [US1] Validate the US1 independent test against the target resource group and record placement, public-network, resource-inventory, and conditional-SQL results in `specs/01-foundry-byo-networking/validation/us1-foundation.md`; report pending work rather than claiming deployment completion

**Checkpoint**: US1 is independently reviewable when its preview and live inspection evidence pass; it does not imply private endpoint, DNS, or model readiness.

## Phase 4: User Story 2 - Enable BYO VNet and Private Name Resolution (Priority: P1)

**Goal**: Connect Foundry and dependencies through the existing private-endpoint subnet and existing DNS zones, with readiness failing closed for unhealthy connectivity.

**Independent Test**: From a private VNet workload, verify every required endpoint is approved, mapped to the correct existing DNS zone/link, and resolves to a private address.

### Implementation for User Story 2

- [ ] T020 [P] [US2] Implement reusable private endpoint creation for confirmed target resource IDs, group IDs, and `snet-privateendpoints` in `infra/modules/foundry/private-endpoint.bicep`
- [ ] T021 [P] [US2] Add DNS zone groups that reference existing Cognitive Services/Foundry, Storage Blob, Key Vault, and conditional Azure OpenAI/SQL zone IDs in `infra/modules/foundry/private-endpoint.bicep`
- [ ] T022 [US2] Wire account, project-as-required, Storage, Key Vault, and conditional SQL private endpoints into `infra/envs/poc/main.bicep` without creating VNets, subnets, DNS zones, or public IPs
- [ ] T023 [US2] Add private endpoint approval-state, DNS-zone-group, VNet-link, subnet placement, and private-resolution checks to `infra/modules/foundry/validation.bicep`
- [ ] T024 [US2] Extend `specs/01-foundry-byo-networking/validation/validate.sh` to inspect PE connections, DNS links, subnet utilization, and private FQDN resolution from a VNet host
- [ ] T025 [US2] Run the private connectivity independent test and record each endpoint state, DNS mapping, resolved address, and remediation for pending/rejected/missing items in `specs/01-foundry-byo-networking/validation/us2-private-connectivity.md`

**Checkpoint**: US2 is ready only when all required PE connections are approved and all tested service names resolve privately; any missing DNS integration or unhealthy endpoint keeps readiness false.

## Phase 5: User Story 3 - Deploy and Validate an Approved Model (Priority: P2)

**Goal**: Deploy exactly one AI CoE-approved model only after private foundation, DNS, quota, and availability gates pass, then prove private-path usability.

**Independent Test**: Make ten controlled requests through the private Foundry endpoint and confirm at least nine succeed against the documented deployment without enabling a public route.

### Implementation for User Story 3

- [ ] T026 [P] [US3] Implement explicit one-deployment parameters and `accounts/deployments` resource using approved model name/version/format, serving option, SKU, and capacity in `infra/modules/foundry/model-deployment.bicep`
- [ ] T027 [US3] Add a preflight assertion that blocks model deployment when quota/availability evidence is absent or failed and never selects a fallback model in `infra/modules/foundry/model-deployment.bicep`
- [ ] T028 [US3] Gate model-module invocation on successful account/project, BYO VNet, PE approval, DNS, and quota checks in `infra/envs/poc/main.bicep`
- [ ] T029 [US3] Add model metadata, quota result, smoke-test result, and readiness aggregation to `infra/modules/foundry/validation.bicep`
- [ ] T030 [US3] Execute the approved private smoke test and ten-request reliability check, recording deployment identity, response status, route, and failures in `specs/01-foundry-byo-networking/validation/us3-model.md`
- [ ] T031 [US3] Validate the insufficient-quota, unavailable-region, and post-agent-BYO-VNet failure paths and document that no alternate model or public endpoint is enabled in `specs/01-foundry-byo-networking/validation/us3-failures.md`

**Checkpoint**: US3 is complete only when the approved model is evidenced as available and the private smoke test meets the 9/10 criterion; otherwise the feature remains incomplete.

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validate idempotency, traceability, governance, and documentation without expanding Chapter 01 scope.

- [ ] T032 [P] Add resource IDs, declared model metadata, prerequisite/managed status, and readiness output wiring to `infra/modules/foundry/validation.bicep`
- [ ] T033 [P] Document platform-engineering versus AI CoE responsibilities, approval gates, manual-provider exception handling, and out-of-scope deployment claims in `specs/01-foundry-byo-networking/README.md`
- [ ] T034 [P] Update `specs/01-foundry-byo-networking/quickstart.md` with the implemented module paths, evidence filenames, and exact preview/validation commands
- [ ] T035 Run a second `az deployment group what-if` with unchanged parameters and compare it with T018 to verify idempotency and no duplicate DNS zones/endpoints/model deployments in `specs/01-foundry-byo-networking/validation/idempotency.md`
- [ ] T036 Run `az bicep build` for every changed module, execute the full validation runner, and attach command output and unresolved limitations to `specs/01-foundry-byo-networking/validation/final-report.md`
- [X] T037 [P] Add a structured Foundry request issue form at `.github/ISSUE_TEMPLATE/foundry-request.yml` for account, project, region, model, capacity, and dependency intake
- [X] T038 [P] Add read-only model/quota preflight automation at `specs/01-foundry-byo-networking/validation/model-preflight.sh`
- [X] T039 Add `.github/workflows/foundry-preflight.yml` to run network/model preflight with Azure OIDC and post a report to the request issue; deployment remains out of scope
- [X] T040 [P] Add provider-neutral Foundry preflight, what-if, and explicit-deployment scripts under `scripts/foundry/`
- [X] T041 [P] Document the shared script contract and Bitbucket adapter example in `scripts/foundry/README.md`

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 has no implementation dependencies and may begin immediately.
- Phase 2 depends on Phase 1 and blocks all Bicep implementation until the live API, private-link, workload, approval, quota, and prerequisite gates are resolved.
- Phase 3 depends on Phase 2; it is the MVP foundation increment.
- Phase 4 depends on the account/project and supporting-resource shape from Phase 3, then can implement endpoint files in parallel with final US1 evidence.
- Phase 5 depends on passing US1 and US2 readiness plus AI CoE quota/model approval; it must not deploy on a failed preflight.
- Phase 6 depends on the desired implementation and validation increments; it records evidence and does not itself claim deployment success.

### User Story Dependencies

- **US1 (P1)**: Starts after Phase 2; no model dependency.
- **US2 (P1)**: Requires the confirmed account/project/supporting-resource target IDs and ordering from US1; its endpoint implementation can be parallelized by file after T011.
- **US3 (P2)**: Requires successful US1 and US2 checks and approved quota/model evidence; it cannot be independently deployed before those gates.

### Parallel Opportunities

- T002-T004 can run in parallel.
- T005-T010 can run in parallel because they are independent read-only research/prerequisite checks.
- After T011, T013-T014 and T020-T021 can be developed in parallel in separate Bicep files; composition tasks wait for confirmed interfaces.
- T026 can be drafted in parallel with T023-T025, but invocation and execution wait for the readiness gates.
- T032-T034 can run in parallel; T035-T036 remain final verification tasks.

## Implementation Strategy

### MVP First

1. Complete Phase 1 and the Phase 2 research/prerequisite checkpoint.
2. Implement and preview US1 only.
3. Validate the foundation increment and stop if the preview or inspection fails.
4. Do not describe the MVP as private-ready until US2 passes.

### Incremental Delivery

1. Add US2 private endpoints/DNS and independently validate private resolution.
2. Add US3 only after quota and private-readiness gates pass.
3. Finish idempotency, evidence, and documentation checks.
4. Report any pending provider approval, quota, or unsupported API capability as incomplete.

## Notes

- `[P]` marks tasks that use different files or independent read-only evidence and can be parallelized.
- Every task includes a concrete repository file path; live Azure commands must save evidence at the named path.
- Existing network and DNS resources are prerequisites and must not be recreated or mutated by this feature.
- Deployment code is not considered deployed merely because it compiles or produces a what-if.
