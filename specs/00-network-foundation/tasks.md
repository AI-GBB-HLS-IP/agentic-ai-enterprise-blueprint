---
description: "Dependency-ordered implementation tasks for the greenfield and brownfield Network Foundation"
---

# Tasks: Network Foundation (Greenfield and Brownfield)

**Input**: Design documents from `specs/00-network-foundation/`

**Prerequisites**: `specs/00-network-foundation/plan.md`, `specs/00-network-foundation/spec.md`,
`specs/00-network-foundation/research.md`, `specs/00-network-foundation/data-model.md`,
`specs/00-network-foundation/contracts/`, `specs/00-network-foundation/quickstart.md`, and
`.specify/memory/constitution.md`

**Tests**: Deterministic validation behavior requires automated shell tests and generic JSON
fixtures. Test tasks must be completed first and demonstrate the expected failure before the
corresponding implementation task receives credit.

**Confidentiality**: Use generic placeholders only. Do not commit discovery output, real parameter
files, tenant or subscription IDs, customer resource names, CIDRs, identities, email addresses,
peer details, or organization-specific policy names.

**Prototype status**: Every current uncommitted infrastructure edit is an unapproved prototype.
File presence, compilability, or prior deployment does not complete any task. Each prototype file
must be compared with the approved design artifacts and then replaced or updated before
implementation credit is given.

## Phase 1: Prototype Reconciliation

**Purpose**: Reconcile every uncommitted infrastructure prototype before implementation work is
credited.

- [X] T001 [P] Compare the prototype deployment instructions in `infra/envs/poc/README.md` with `specs/00-network-foundation/plan.md` and replace or update every conflicting greenfield, brownfield, ownership, approval, recovery, and confidentiality instruction
- [ ] T002 [P] Compare the prototype composition in `infra/envs/poc/main.bicep` with the approved greenfield boundaries and replace or update it without treating any existing resource declaration as complete
- [ ] T003 [P] Compare the prototype network-related changes in `infra/modules/foundry/supporting-resources.bicep` with the Network Foundation ownership boundary and remove or update assumptions not approved by `specs/00-network-foundation/plan.md`
- [X] T004 [P] Compare the prototype module documentation in `infra/modules/network/README.md` with the approved mode, scope, ownership, sizing, DNS, NSG, route-table, and Bastion contracts and replace or update conflicting content
- [ ] T005 [P] Compare the prototype Bastion implementation in `infra/modules/network/bastion.bicep` with the optional-Bastion requirements for both modes and replace or update it before claiming implementation credit
- [ ] T006 [P] Compare the prototype greenfield network module in `infra/modules/network/main.bicep` with the fixed greenfield contract and shared-module boundaries and replace or update every nonconforming declaration
- [ ] T007 [P] Compare `infra/envs/poc/existing-vnet.bicep` with the approved network-owner stage, then replace it with or migrate it into `infra/envs/poc/brownfield-network.bicep` so the obsolete prototype is not retained as an alternative deployment path
- [ ] T008 [P] Compare `infra/envs/poc/existing-vnet.bicepparam` with the approved parameter contract, then replace it with `infra/envs/poc/brownfield-network.bicepparam.example` and ensure no real deployment values remain tracked
- [ ] T009 [P] Compare the prototype subnet module in `infra/modules/network/subnets.bicep` with the approved child-resource-only and serialized-write design and replace or update every nonconforming declaration

**Checkpoint**: Every prototype has an explicit reconciliation result; no implementation task is
complete solely because prototype code already exists.

---

## Phase 2: Foundational Validation and Confidentiality

**Purpose**: Establish shared test, evidence, and confidentiality controls that block all user
stories.

**CRITICAL**: No user-story implementation receives credit until this phase and Phase 1 are
complete.

- [X] T010 Create the deterministic network test runner in `tests/network/run-tests.sh` and configure it to execute every `tests/network/test-*.sh` file with fail-fast exit handling
- [X] T011 [P] Add ignore rules for local discovery output, real brownfield parameters, live approval evidence, and temporary what-if output in `.gitignore`
- [X] T012 [P] Create generic redacted success and failure fixture guidance in `tests/network/fixtures/README.md`, permitting placeholders and documentation-only address examples but no discovery-derived values
- [X] T013 [P] Add failing confidentiality cases for identifiers, identities, emails, CIDRs, peer data, absolute discovery paths, raw parameters, and organization-specific policy names in `tests/network/test-scan-confidentiality.sh`
- [X] T014 Implement the repository confidentiality gate in `scripts/network/scan-confidentiality.sh` so it fails closed on prohibited discovery-derived data while permitting approved placeholders and greenfield constants
- [X] T015 [P] Define generic redacted evidence fields for discovery, capacity approval, ownership, scoped what-if, deployment, idempotency, DNS resolution, recovery, and confidentiality in `specs/00-network-foundation/contracts/validation-evidence.md`
- [X] T072 [P] Add failing tests for SC-010 covering missing, null, non-boolean, or `false` `publicNetworkAccessDisabled` and `localAuthDisabled` values, plus missing, empty, duplicate, whitespace-only, wildcard, and pattern entries in `allowedModelSkus`, in `tests/network/test-validate-policy-inputs.sh`
- [X] T073 Implement the fail-closed policy-input validator in `scripts/network/validate-policy-inputs.sh` (FR-019, FR-020), requiring both policy booleans to be present and `true` and requiring `allowedModelSkus` to be a non-empty array of unique, non-empty, exact SKU strings without wildcards or patterns; do not evaluate downstream resource settings or selected SKUs

**Checkpoint**: The test harness and confidentiality gate are ready, and repository artifacts have
a generic evidence contract, including the policy-input validation contract.

---

## Phase 3: User Story 3 - Confirm Region and Quota (Priority: P1)

**Goal**: Block infrastructure deployment until the selected region, provider registration,
permissions, and Foundry/OpenAI quota have been confirmed without committing live subscription
details.

**Independent Test**: Supply generic fixtures representing missing provider registration,
insufficient quota, missing approval, and approved prerequisites; verify that only the fully
approved fixture passes.

### Tests for User Story 3

- [ ] T016 [P] [US3] Add failing tests for inactive subscriptions, wrong tenant or subscription scope, unregistered `Microsoft.Network`, missing deployment access, absent quota evidence, and insufficient quota decisions in `tests/network/test-validate-deployment-prerequisites.sh`

### Implementation for User Story 3

- [ ] T017 [US3] Implement the read-only prerequisite and quota-approval validator in `scripts/network/validate-deployment-prerequisites.sh` using Azure CLI queries plus an untracked approval input, with redacted status-only output
- [ ] T018 [US3] Document prerequisite queries, traffic-estimate comparison, quota-increase fallback, approval requirements, and the prohibition on committed live quota output in `infra/envs/poc/README.md`

**Checkpoint**: Region and quota approval can be verified without exposing subscription-specific
information.

---

## Phase 4: User Story 1 - Provision the Greenfield Network (Priority: P1)

**Goal**: Preserve a deployable, idempotent greenfield VNet containing five fixed workload
subnets, required NSGs, and blueprint-owned Private DNS zones and links.

**Independent Test**: Build and preview `infra/envs/poc/main.bicep` against an empty resource
group; verify the fixed VNet and five workload subnets, Foundry delegation, NSG associations, and
required Private DNS zones and links are present, while no Bastion resources appear when disabled.

### Tests for User Story 1

- [ ] T019 [P] [US1] Add failing compiled-template assertions for the fixed greenfield VNet, five subnet prefixes, purpose-keyed behavior, Foundry delegation, NSG associations, required Private DNS zones, VNet links, and disabled-by-default Bastion in `tests/network/test-greenfield-template.sh`
- [ ] T020 [P] [US1] Add failing allowlist tests for greenfield what-if changes, deletes, public IP exceptions, and idempotent no-change results in `tests/network/test-validate-greenfield-what-if.sh`

### Implementation for User Story 1

- [ ] T021 [P] [US1] Implement or reconcile the blueprint-owned greenfield VNet and fixed workload subnet composition in `infra/modules/network/main.bicep` without introducing a brownfield mode switch
- [ ] T022 [P] [US1] Implement or reconcile purpose-keyed subnet declarations, Foundry `Microsoft.App/environments` delegation, and private-endpoint network-policy settings in `infra/modules/network/subnets.bicep`
- [ ] T023 [P] [US1] Implement or reconcile blueprint-owned APIM and compute NSGs, including approved APIM control-plane requirements and the compute gateway-path restriction, in `infra/modules/network/nsg.bicep`
- [ ] T024 [P] [US1] Implement or reconcile blueprint-owned Private DNS zones and registration-disabled VNet links for active greenfield service roles in `infra/modules/network/private-dns.bicep`
- [ ] T025 [US1] Compose the reconciled greenfield network, NSG, subnet, and DNS modules with optional Bastion disabled by default in `infra/envs/poc/main.bicep`
- [ ] T026 [P] [US1] Reconcile fixed greenfield defaults and the generic policy tag object in `infra/envs/poc/network.parameters.json`, applying tags only to blueprint-owned resources
- [ ] T027 [US1] Implement the greenfield preview boundary and idempotency validator in `scripts/network/validate-greenfield-what-if.sh`
- [ ] T028 [US1] Add stable VNet, purpose-keyed subnet, NSG, DNS-link, optional Bastion, and structured readiness outputs in `infra/modules/network/main.bicep`
- [ ] T029 [US1] Run the independent greenfield validation flow from `specs/00-network-foundation/quickstart.md`, fixing `infra/envs/poc/main.bicep` and referenced modules until the compiled template, scoped what-if, post-deployment checks, and unchanged rerun satisfy the story contract

**Checkpoint**: Greenfield mode is independently deployable and idempotent with no public IP when
Bastion is disabled.

---

## Phase 5: User Story 4 - Integrate with an Existing VNet (Priority: P1)

**Goal**: Discover an existing VNet read-only, obtain capacity approval, create only approved new
blueprint subnets and associations, and deploy existing-zone VNet links through separate
owner-scoped stages.

**Independent Test**: Using generic fixtures and approved untracked parameters, run discovery,
capacity calculation, network preflight, network what-if validation, DNS preflight, and DNS
what-if validation. Verify that only approved new subnets, approved associations, blueprint-owned
NSGs, and existing-zone VNet links are allowed.

### Discovery and Capacity Tests

- [ ] T030 [P] [US4] Add failing tests proving discovery uses read-only Azure operations and inventories VNet prefixes, subnet names and CIDRs, delegations, NSG and route-table associations, peerings, DNS configuration, DDoS settings, and unallocated ranges in `tests/network/test-discover-existing-vnet.sh`
- [ ] T031 [P] [US4] Add failing capacity tests for missing IPAM evidence, Azure-reserved addresses, insufficient growth allowance, Foundry prefixes smaller than `/27`, Foundry allocations below `/26` without rationale, classic Premium APIM prefixes smaller than `/29`, APIM allocations below `/27` without rationale, and workload-derived private endpoint, compute, and CI/CD sizing in `tests/network/test-calculate-subnet-capacity.sh`

### Discovery and Capacity Implementation

- [ ] T032 [US4] Implement read-only existing-VNet discovery and local JSON output in `scripts/network/discover-existing-vnet.sh`, ensuring it proposes no changes and never writes discovery values into repository artifacts
- [ ] T033 [US4] Implement service-profile and workload-derived capacity calculation in `scripts/network/calculate-subnet-capacity.sh`, including minimums, recommendations, expected consumers, Azure-reserved addresses, growth allowance, rationale, and generic IPAM approval status
- [ ] T034 [P] [US4] Define placeholder-only discovery, capacity, deployment-key, ownership, adoption, NSG, route-table, and subnet-request inputs in `infra/envs/poc/brownfield-network.bicepparam.example`

### Brownfield Preflight Tests

- [ ] T035 [P] [US4] Add failing tests for duplicate requested names, existing customer-managed names, malformed CIDRs, containment failures, overlaps with existing subnets, and overlaps among requested subnets in `tests/network/test-brownfield-address-validation.sh`
- [ ] T036 [P] [US4] Add failing tests for delegation, private-endpoint policy, Foundry, classic Premium APIM, private endpoint, compute, CI/CD, and growth-headroom rules in `tests/network/test-brownfield-service-profiles.sh`
- [ ] T037 [P] [US4] Add failing tests for missing prior deployment ownership, mismatched deployment keys, changed live subnet properties, implicit adoption, incomplete adoption approval, and exact-match adoption fallback in `tests/network/test-brownfield-ownership.sh`
- [ ] T038 [P] [US4] Add failing tests for cross-tenant references, VNet and blueprint resource groups in different subscriptions, unresolved or unapproved NSGs, unresolved or unapproved route tables, and missing read or association permissions in `tests/network/test-brownfield-scope-and-references.sh`

### Brownfield Preflight Implementation

- [ ] T039 [US4] Implement fail-closed brownfield preflight in `scripts/network/validate-brownfield-inputs.sh`, covering discovery evidence, IPAM approval, sizing, names, containment, overlap, service behavior, same-subscription boundary, permissions, prior ownership, adoption fallback, existing NSGs, and existing route tables
- [ ] T040 [P] [US4] Implement the existing-zone link-only child module with registration fixed to `false` in `infra/modules/network/private-dns-link.bicep`
- [ ] T041 [P] [US4] Add failing static and compiled-template assertions for existing VNet immutability, child-only subnet writes, absence of route resources, existing-control immutability, and link-only DNS behavior in `tests/network/test-brownfield-template-boundaries.sh`
- [ ] T042 [P] [US4] Implement new-subnet child resources with `@batchSize(1)` serialized writes and no existing VNet property declaration in `infra/modules/network/subnets.bicep`
- [ ] T043 [P] [US4] Implement blueprint-owned NSG creation and approved-existing-NSG reference handling without modifying referenced NSGs in `infra/modules/network/nsg.bicep`
- [ ] T044 [US4] Implement the network-owner entry point in `infra/envs/poc/brownfield-network.bicep`, deploying the root at blueprint resource-group scope while invoking subnet writes at existing-VNet resource-group scope in the same subscription
- [ ] T045 [P] [US4] Ensure `infra/envs/poc/brownfield-network.bicepparam.example` contains only placeholders and documents that existing route-table IDs are references only and no route tables or routes are created

### Network-Owner Preview Tests and Implementation

- [ ] T046 [P] [US4] Add failing network what-if tests for VNet modifications, customer-managed subnet changes, deletes, existing NSG changes, route-table or route changes, DNS changes, unrelated resources, unauthorized associations, and unexpected Bastion resources in `tests/network/test-validate-network-what-if.sh`
- [ ] T047 [US4] Implement the scoped network-owner what-if validator in `scripts/network/validate-network-what-if.sh`, allowing only approved new subnets, blueprint-owned NSGs, approved associations, ownership-matched reruns, and explicitly enabled Bastion resources

### DNS-Owner Tests and Implementation

- [ ] T048 [P] [US4] Add failing DNS preflight tests for unresolved zones, cross-tenant scopes, mixed subscription or resource-group ownership in one invocation, missing link permissions, unapproved VNets, duplicate link names, unrelated existing links, and enabled registration in `tests/network/test-validate-dns-inputs.sh`
- [ ] T049 [US4] Implement read-only existing-zone and VNet-link preflight validation in `scripts/network/validate-dns-inputs.sh`
- [ ] T050 [US4] Implement the DNS-owner resource-group-scoped entry point in `infra/envs/poc/brownfield-dns.bicep`, requiring one explicit DNS subscription and resource group per invocation and creating only links beneath approved existing zones
- [ ] T051 [P] [US4] Create the placeholder-only, single-owner-scope DNS parameter example in `infra/envs/poc/brownfield-dns.bicepparam.example`
- [ ] T052 [P] [US4] Add failing DNS what-if tests for zone creation or modification, record-set changes, deletes, unrelated resources, unapproved zones or VNets, and registration-enabled links in `tests/network/test-validate-dns-what-if.sh`
- [ ] T053 [US4] Implement the DNS-owner what-if validator in `scripts/network/validate-dns-what-if.sh`, allowing only approved existing-zone VNet-link changes with registration disabled

### Ownership, Recovery, and Idempotency

- [ ] T054 [US4] Add deployment-key, managed-subnet property, association, optional Bastion, and structured network-stage status outputs in `infra/envs/poc/brownfield-network.bicep`
- [ ] T055 [US4] Add service-role-keyed VNet-link IDs, zone-reference status, private-resolution status, and structured DNS-stage status outputs in `infra/envs/poc/brownfield-dns.bicep`
- [ ] T056 [US4] Add deterministic stage-state, changed-parameter reapproval, independent retry, roll-forward recovery, and unchanged-rerun tests in `tests/network/test-brownfield-stage-lifecycle.sh`
- [ ] T057 [P] [US4] Document discovery, capacity calculation, IPAM evidence, untracked parameters, network-owner deployment, per-owner-scope DNS deployment, downstream blocking, roll-forward recovery, and idempotency in `specs/00-network-foundation/quickstart.md`

**Checkpoint**: Brownfield network and DNS stages are independently previewable, approvable,
deployable, retryable, and idempotent without taking ownership of existing infrastructure.

---

## Phase 6: User Story 2 - Optionally Enable Bastion (Priority: P2)

**Goal**: Allow Bastion in greenfield and brownfield modes only when explicitly enabled, while
ensuring disabled mode produces no Bastion subnet, host, or public IP.

**Independent Test**: Build and preview both entry points with Bastion disabled and enabled.
Verify zero Bastion resources when disabled and exactly the approved subnet, host, and public IP
exception when enabled.

### Tests for User Story 2

- [ ] T058 [P] [US2] Add failing compiled-template and what-if tests for Bastion enabled and disabled states in both modes, including fixed subnet naming, minimum prefix, public IP exception, resource scope, and absence of partial resources in `tests/network/test-bastion-modes.sh`

### Implementation for User Story 2

- [ ] T059 [US2] Implement or reconcile fully conditional Bastion host and public IP resources in `infra/modules/network/bastion.bicep`, applying tags only to blueprint-owned resources
- [ ] T060 [P] [US2] Wire optional Bastion subnet and module deployment into greenfield mode in `infra/envs/poc/main.bicep`
- [ ] T061 [P] [US2] Wire optional `AzureBastionSubnet` creation at existing-VNet resource-group scope and Bastion host/public IP creation at blueprint resource-group scope in `infra/envs/poc/brownfield-network.bicep`
- [ ] T062 [P] [US2] Document Bastion-enabled validation and an approved non-Bastion in-network DNS validation alternative without adding a persistent test VM in `specs/00-network-foundation/quickstart.md`
- [ ] T063 [US2] Run enabled and disabled previews for `infra/envs/poc/main.bicep` and `infra/envs/poc/brownfield-network.bicep`, fixing modules until `tests/network/test-bastion-modes.sh` and both scoped what-if gates pass

**Checkpoint**: Bastion is fully optional in both modes, and its public IP is the only permitted
public-IP exception.

---

## Phase 7: Polish and Cross-Cutting Validation

**Purpose**: Complete executable documentation and run all merge gates across both modes.

- [ ] T064 [P] Reconcile deployment parameter documentation with implemented inputs, sizing evidence, ownership rules, placeholders, and owner scopes in `specs/00-network-foundation/contracts/deployment-parameters.md`
- [ ] T065 [P] Reconcile allowed changes, forbidden changes, preview assertions, and outputs with the implemented network stage in `specs/00-network-foundation/contracts/network-stage.md`
- [ ] T066 [P] Reconcile allowed changes, forbidden changes, per-scope invocation, recovery behavior, and outputs with the implemented DNS stage in `specs/00-network-foundation/contracts/dns-stage.md`
- [ ] T067 Run the deterministic validation suite through `tests/network/run-tests.sh` and fix every failure in the referenced `scripts/network/`, `infra/modules/network/`, and `infra/envs/poc/` files
- [ ] T068 Run final Bicep builds for `infra/envs/poc/main.bicep`, `infra/envs/poc/brownfield-network.bicep`, `infra/envs/poc/brownfield-dns.bicep`, and `infra/modules/foundry/supporting-resources.bicep`, fixing all warnings or errors in those files and referenced modules
- [ ] T069 Execute the greenfield, brownfield network-owner, and per-owner-scope DNS what-if workflows in `specs/00-network-foundation/quickstart.md`, validate each result with its corresponding `scripts/network/validate-*-what-if.sh` gate, and verify unchanged reruns contain no unexpected changes
- [ ] T070 Run `scripts/network/scan-confidentiality.sh` across tracked artifacts and remove every customer-specific discovery value, identity, email, resource name, ID, CIDR, peer detail, absolute discovery path, real parameter value, and organization-specific policy name reported
- [ ] T071 Perform the final constitution and readiness review against `.specify/memory/constitution.md` and record generic remediation instructions in `infra/envs/poc/README.md` before requesting Platform Engineering review
- [ ] T074 [SC-010] Add failing assertions for a readiness output produced without a `policy-compliant` status or with policy-input values changed during handoff, add a `policy-compliant` field to the structured readiness outputs in `infra/envs/poc/main.bicep` and `infra/envs/poc/brownfield-network.bicep`, and block the downstream-release step in `specs/00-network-foundation/quickstart.md` until network, DNS, and policy-input status are all `ready`/`policy-compliant`

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1** starts immediately and reconciles every prototype file.
- **Phase 2** can begin alongside independent Phase 1 reviews but must finish before user-story
  implementation receives credit.
- **User Story 3** depends on Phase 2 and blocks live deployment approval.
- **User Story 1** depends on Phases 1 and 2.
- **User Story 4** depends on Phases 1 and 2 and shares reconciled subnet and NSG modules with US1.
- **User Story 2** depends on the applicable US1 or US4 composition.
- **Phase 2** includes T072-T073, the generic FR-019/FR-020 policy-input tests and validator; they
  can run with the other foundational validation work and before user-story implementation.
- **Phase 7** depends on all stories included in the release. T074 completes the readiness-output
  wiring and must finish after T028 (US1) and T054 (US4) add their respective structured outputs.

### User Story Dependency Graph

```text
Phase 1: Prototype reconciliation
              |
Phase 2: Tests, evidence, confidentiality
              |
       +------+-------------------+
       |                          |
US3: Region/quota            Shared module baseline
       |                          |
       |                  +-------+-------+
       |                  |               |
       +--------------> US1             US4
                    Greenfield       Brownfield
                         \             /
                          +-----+-----+
                                |
                         US2: Bastion
                                |
                         Final validation
```

### User Story 4 Execution Order

```text
Discovery tests
  -> read-only discovery
  -> capacity tests and calculation
  -> IPAM approval
  -> address, sizing, ownership, and scope tests
  -> brownfield preflight
  -> subnet, NSG, and network composition
  -> network what-if validator
  -> network-owner approval and readiness
  -> DNS input validation and link-only composition
  -> DNS what-if validator
  -> DNS-owner approval and readiness
  -> idempotency and roll-forward recovery
```

## Parallel Execution Examples

### Prototype Reconciliation

T001-T009 can run in parallel because each task owns a different prototype file.

### User Story 1

```text
First: T019 and T020
Then in parallel: T021, T022, T023, T024, T026
Then: T025, T027, T028, T029
```

### User Story 4

```text
First in parallel:
T030, T031, T035, T036, T037, T038, T041, T046, T048, T052

Then by workstream:
- Discovery and capacity: T032-T034
- Shared modules: T040, T042, T043
- Validators: T039, T047, T049, T053
- Parameter examples: T045, T051

Integration:
T044 -> network approval/readiness -> T050 -> T054-T057
```

### User Story 2

```text
T058 -> T059 -> T060, T061, T062 in parallel -> T063
```

## Implementation Strategy

### MVP

1. Complete prototype reconciliation and foundational controls.
2. Complete US3 so region and quota approval block unsafe deployment.
3. Preserve and independently validate US1.
4. Complete US4 through network and DNS readiness.
5. Keep US2 disabled unless Bastion is explicitly required.

### Incremental Delivery

1. Reconciliation and confidentiality controls.
2. Greenfield preservation.
3. Brownfield discovery, capacity, and network stage.
4. Brownfield DNS stage.
5. Optional Bastion.
6. Final validation and review.

## Notes

- `[P]` identifies work that can proceed in parallel because it targets different files and does
  not depend on incomplete implementation in the same file.
- `[US1]`, `[US2]`, `[US3]`, and `[US4]` map tasks to specification user stories.
- T072-T074 map to FR-019/FR-020 and are cross-cutting (no user-story tag) because they validate a
  generic policy-input parameter contract this spec forwards to the Foundry/APIM specs rather than
  enforcing on a resource this spec creates. T072-T073 are foundational; T074 is final
  integration wiring. T072 and T074 provide the measurable test coverage for SC-010.
- All tasks remain unchecked because the current infrastructure changes are unapproved prototypes.
- Tests defining deterministic validation must be added first and shown to fail before
  corresponding implementation receives credit.
- Live discovery output, real parameters, and unredacted approval evidence remain outside Git.
- Brownfield recovery is roll-forward only.
- Changed approved parameters return the affected stage to preview and approval.
