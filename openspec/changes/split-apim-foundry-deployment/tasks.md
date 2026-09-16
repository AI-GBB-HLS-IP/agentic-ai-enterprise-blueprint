## 1. Align Chapter 02 Requirements and Guidance

- [x] 1.1 Revise `chapters/02-ai-gateway.md` to introduce the APIM foundation and Foundry
  integration stages, state their independent Azure prerequisites, and verify the foundation
  walkthrough contains no Foundry-dependent command or input.
- [x] 1.2 Update `specs/02-apim-ai-gateway/spec.md`, `plan.md`, `data-model.md`, `research.md`, and
  `contracts/apim-bicep-interface.md` with stage ownership, inputs, outputs, readiness, and
  rollback boundaries; verify all documents consistently assign DNS and monitoring to foundation
  and role/backend/model/API resources to integration.
- [x] 1.3 Reorganize `specs/02-apim-ai-gateway/tasks.md` and `quickstart.md` into stage-specific
  prerequisites, deployment commands, checkpoints, and evidence paths; verify an operator can
  complete the documented Stage 1 flow while Foundry is unavailable.
- [x] 1.4 Add a customer-alignment matrix to the Chapter 02 planning or validation documentation
  covering the VPCx Azure 2.0 APIM and Foundry controls, including any evidenced tenant-specific
  exception; verify every applicable customer control maps to a template input, validation check,
  policy-owned control, or explicitly conditional step.

## 2. Decouple the APIM Foundation Infrastructure

- [x] 2.1 Refactor `infra/modules/apim/main.bicep` to deploy only APIM and its system-assigned
  identity, accept the customer-approved public IP required by classic internal mode, and remove
  all Foundry parameters, references, role assignment composition, and Foundry readiness fields;
  verify `az bicep build --file infra/modules/apim/main.bicep` succeeds.
- [x] 2.2 Refactor `infra/envs/poc/apim.bicep` to compose only the APIM service, private DNS, and
  observability modules with foundation-only readiness outputs; verify the compiled template has
  no `Microsoft.CognitiveServices`, Foundry backend, approved-model, or governed API resources.
- [x] 2.3 Reduce `infra/envs/poc/apim.bicepparam` to network, APIM, DNS, policy-handoff, and
  monitoring inputs, including the approved public IP; verify no parameter name or value
  references Foundry, models, backend, product, token limits, or the governed AI API.
- [x] 2.4 Validate the APIM subnet name, approved NSG, route table or documented active-policy
  exception, no-delegation state, and four required service endpoints against the customer policy
  profile; verify a noncompliant subnet fails before APIM provisioning.
- [x] 2.5 Configure or verify the customer APIM security baseline for Premium tier, corporate
  administrator email, internal VNet mode, HTTPS backends, TLS 1.2 or stronger, and disabled weak
  protocols/ciphers; verify the compiled settings pass the static compliance checks.
- [x] 2.6 Extend foundation observability to collect AllLogs and AllMetrics through the
  policy-required diagnostic destination and add or verify the average-capacity-above-60-percent
  alert; verify policy-owned diagnostic settings are detected without an attempted conflicting
  replacement.
- [x] 2.7 Document the optional enterprise custom-domain path with approved CA certificates and
  internal DNS A records to the APIM private VIP; verify the default VNet-local path does not
  require a custom domain.
- [x] 2.9 Simplify the POC smoke-test contract so the foundation template creates the approved
  Standard/static APIM public IP and operators use one ignored `apim.customer.bicepparam` for
  direct Azure validate, what-if, and create commands.
- [x] 2.10 Standardize every tracked `.bicepparam` assignment on typed
  `readEnvironmentVariable(...)` inputs and enforce the convention in Chapter 02 validation.
- [x] 2.11 Add external APIM DNS mode for VPCx environments that deny workload-owned private DNS,
  preserving blueprint-owned DNS for environments where policy permits it and emitting an
  explicit customer DNS handoff.
- [ ] 2.8 Run the foundation `what-if` without Foundry parameters and record evidence showing only
  foundation-owned changes and no Foundry lookup or permission requirement.

## 3. Add the Deferred Foundry Integration Infrastructure

- [x] 3.1 Add `infra/envs/poc/apim-foundry-integration.bicep` that references an existing APIM
  service and composes `foundry-role-assignment.bicep`, `backend.bicep`, and `api.bicep`; verify
  the compiled template does not declare the APIM service, private DNS zone, or monitoring
  resources.
- [x] 3.2 Add `infra/envs/poc/apim-foundry-integration.bicepparam` with existing APIM, Foundry,
  approved-model, backend, API, product, token policy, and API-version inputs; verify it contains
  no foundation deployment settings beyond the APIM reference needed for integration.
- [x] 3.3 Add integration preflight for customer GenAI approval/account enablement evidence,
  approved Foundry region, private endpoint posture, and customer-approved model allowlisting;
  verify none of these checks execute in foundation mode.
- [x] 3.4 Ensure the integration entry point derives the APIM principal from the existing APIM
  resource and scopes `Cognitive Services OpenAI User` only to the selected Foundry account;
  verify the generated ARM template contains the expected account-scoped role assignment.
- [x] 3.5 Expose integration-only outputs for role assignment, backend, governed API, product,
  model mapping, and readiness; verify a missing Foundry account or approved model causes an
  integration prerequisite failure without proposing changes to foundation-owned resources.
- [ ] 3.6 Run the integration `what-if` against a validated APIM foundation and approved Foundry
  environment, recording evidence that only integration-owned resources are added or updated.

## 4. Split Validation and Evidence

- [x] 4.1 Refactor `specs/02-apim-ai-gateway/validation/validate.sh` to support explicit
  `foundation`, `integration`, and `all` modes; verify `foundation` mode performs no
  `az cognitiveservices` or Foundry role/backend/API check.
- [x] 4.2 Add foundation validation for subnet readiness, APIM internal VNet injection, managed
  identity, required classic-tier public IP, private endpoint reachability, DNS, protocol
  settings, diagnostics, and capacity monitoring, with a standalone readiness result; verify it
  can pass while integration is reported as not deployed or pending.
- [x] 4.3 Add integration validation for APIM identity discovery, Foundry/model prerequisites,
  least-privilege role scope, managed-identity backend policy, approved-model mapping,
  subscription enforcement, and governed API inventory; verify failures are attributed only to
  integration readiness.
- [x] 4.4 Split or relabel validation evidence under
  `specs/02-apim-ai-gateway/validation/` so foundation preview/runtime evidence is distinct from
  integration preview/request/telemetry evidence; verify `final-report.md` reports both stage
  statuses separately.
- [x] 4.5 Add static regression checks that fail if foundation files regain Foundry references or
  if integration templates declare foundation-owned resources; verify the checks detect seeded
  cross-stage references and pass on the intended templates.
- [x] 4.6 Replace any assertion that internal APIM must have no public IP resource with checks that
  its service endpoints are internal and not publicly reachable; verify the customer-required
  platform public IP does not produce a false exposure failure.

## 5. Verify Staged Deployment Behavior

- [x] 5.1 Build every APIM Bicep module and both environment entry points, then run the repository
  Chapter 02 validation suite; verify all offline checks pass.
- [ ] 5.2 Re-run the foundation deployment preview with unchanged inputs and verify no duplicate or
  unexpected APIM, identity, DNS, network, or monitoring changes are proposed.
- [ ] 5.3 Re-run the integration deployment preview with unchanged inputs and verify no duplicate
  role assignment, backend, model mapping, API, product, or policy resources are proposed.
- [ ] 5.4 Deploy or inspect Stage 1 in an authorized Azure environment and verify APIM foundation
  readiness independently of Foundry availability.
- [ ] 5.5 After Foundry approval, deploy or inspect Stage 2 and verify authorized requests reach
  the approved model, unsupported models and unauthenticated requests fail before Foundry, and
  telemetry remains attributable without logging secrets or payloads.
- [ ] 5.6 Update GitHub issue #71 with the final evidence links and completion status, then verify
  the implementation pull request references the issue and all staged acceptance criteria.
