# Tasks

## 1. Reconcile the endpoint contract

- [x] 1.1 Reconcile Chapter 02 `spec.md`, `plan.md`, `tasks.md`, contracts, and the active
  staged-deployment/custom-domain changes with design D1-D5 and its coverage matrix.
  Record the supported mode matrix, default compatibility, and custom legacy portal/SCM
  client exclusions; verify every requirement/scenario has an implementation and acceptance
  owner and run `openspec validate support-apim-custom-endpoint-access --strict`.

## 2. Foundation selection and validation

- [x] 2.1 After 1.1, implement foundation endpoint/access-path inputs, effective-binding
  checks, selected gateway output, mode-aware DNS handoff, and context-bound evidence/readiness
  in the foundation and DNS module. Wire both foundation parameter files; retain the existing
  built-in output and certificate helpers. Update foundation documentation concurrently.
  Verify Bicep compile plus evaluated tests for built-in default, both DNS owners,
  custom/external/direct, custom/external/corporate, explicit custom/blueprint rejection,
  other invalid combinations/hostnames,
  absent evidence pending, context-matching `status: pass` evidence ready, and mismatched
  evidence rejection. Verify `fail`, `blocked`, missing status, and invalid status cannot
  produce deployed custom readiness. Require all exact D3 base fields (`validationType`,
  `status`, `owner`, `scope`, `approvalReference`, `evidenceSummary`, `timestampUtc`) and
  extension fields (`apimServiceId`, `endpointMode`, `endpointAccessPath`, `selectedHostnames`,
  `validationReference`, plus corporate-only `routingApprovalReference`); test missing,
  empty, and wrong-type fields, wrong gate/owner, and timestamp aliases failing the
  required-field guard. Keep base fields generic and live extension context untracked.
- [x] 2.2 After 2.1, update foundation/all runtime validation for role-matched live bindings,
  direct-private equality, and corporate evidence plus DNS/TLS. Document the evidence JSON
  as an extension of the generic validation contract with every exact base/extension field
  from D3, network-owner approval, missing-access BLOCKED behavior, and distinctions
  between measured checks and operator attestation. Add mocked checks proving custom mode
  performs no built-in probes, rejects wrong bindings/TLS failures/unproven routing, and
  requires all three roles. Include explicit pass/fail/blocked outcomes and tests rejecting
  non-pass evidence as readiness proof. Test a complete conforming record and rejection
  when each required field is absent, empty, or of the wrong type; test incorrect gate/owner,
  invalid ISO-8601 UTC `timestampUtc`, and aliases that omit `timestampUtc`.
  Verify tests and shell syntax without using secrets.

## 3. Integration and operator workflow

- [x] 3.1 After 2.1 and 2.2, extend Stage 2 handoff validation and both integration parameter
  files for selected endpoints, live gateway binding, legacy built-in compatibility, and
  custom context mismatches. Derive the selected client URL and validate explicit request
  overrides before credentials are used. Add tests for same-service custom handoffs, wrong
  service/selection, custom non-pass handoffs (even with overall status deployed), legacy
  defaults, and conflicting/non-HTTPS/userinfo/path overrides. Test non-443-port rejection
  before credentials are used and acceptance of implicit 443 and explicit `:443`;
  reject custom evidence missing any D3 base/extension field or with invalid types,
  gate/owner, or `timestampUtc`, including alias-only timestamps, even if overall
  readiness claims deployed. Check both preflight and Bicep structural guards.
  Verify Stage 2 compilation and no APIM/DNS/observability mutation in structural checks.
- [x] 3.2 After 3.1, update README, Stage 1 smoke guide, validation README, foundation and
  integration evidence templates, request examples, and existing gateway consumers for
  selected URLs. Explain blocked Azure-managed client names versus unchanged platform
  dependencies, manual PFX redeployment, separate Foundry private connectivity, and
  WSL/Windows environment forwarding without logging secrets. Verify documented variables
  match templates/validator and scan committed examples for confidentiality. Cover every
  repository-relative consumer in design D5: project/portal URL storage and onboarding,
  agent/evaluator/CI `APIM_GATEWAY_URL`, MCP/A2A and UI gateway URLs, and selected
  developer-portal metadata. Preserve route suffixes and independent API Center/Foundry
  backend URLs; label the separate Chapter 14 topology as excluded. Keep generic base
  evidence fields redacted and use placeholders for deployment extension fields.

## 4. Cross-surface acceptance

- [x] 4.1 After 1.1, 2.1, 2.2, 3.1, and 3.2, run the smallest existing regressions covering
  the complete revision: `bash tests/foundry/test-apim-staged-contracts.sh`,
  `bash tests/foundry/test-apim-review-regressions.sh`,
  `bash tests/foundry/test-apim-hostname-capture.sh`, and
  `bash tests/network/test-apim-hostnames.sh`, plus new endpoint evaluated/mocked cases,
  Bicep builds, and `openspec validate support-apim-custom-endpoint-access --strict`.
  Verify the generic evidence contract's exact base fields against every input/handoff,
  documentation shape, and positive/negative test, including invalid/missing `timestampUtc`.
  Check each D5 consumer's selected URL handoff, absence of custom built-in fallbacks,
  preserved route suffixes, and independent backend/topology boundaries.
  Review the entire diff and D5 mapping; record exact outcomes separately from live evidence.
- [ ] 4.2 After 4.1, an authorized operator/network owner supplies standard/direct and
  custom approved-path evidence, foundation what-if, retained custom bindings/TLS,
  recorded handoff from the exact deployment, and Stage 2 preview/model request/telemetry
  evidence. Prove custom validation works when built-in client names are unavailable and
  independently verify private Foundry connectivity and managed-identity authorization.
  Store raw evidence only in the customer-approved location and commit only redacted
  dispositions. Missing access or route approval is BLOCKED and prevents deployment
  acceptance; this task is not satisfied by proposal validation or ARM deployment success.

## Workflow follow-up

- Keep #104 open through implementation and mandatory acceptance; a proposal PR does not
  close the feature or unblock a customer deployment.
- Archive only after implemented requirements and evidence dispositions meet the review gate.
