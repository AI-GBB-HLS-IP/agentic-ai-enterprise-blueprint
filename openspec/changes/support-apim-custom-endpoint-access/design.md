# Design

## Context

See `proposal.md` for motivation. Current `private-dns.bicep` always emits five built-in
names; `apim.bicep` fixes its zone/record contract to `azure-api.net`; runtime
`validate_apim_endpoint_reachability` in the Chapter 02 validator requires private-IP
equality for all five. `apim-foundry-integration.bicep` checks readiness but does not
know endpoint selection. Its request validator defaults to the built-in gateway.

Feasibility sources:

- [Internal VNet](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet):
  endpoints require operator DNS; Internal mode and network dependencies remain.
- [Custom domains](https://learn.microsoft.com/en-us/azure/api-management/configure-custom-domain):
  configured Host headers and matching certificates are supported; custom non-gateway
  domains replace defaults, while the default gateway remains configured.
- `infra/modules/apim/hostnames.bicep`: existing certificate expansion/merge must remain intact.
- `infra/envs/poc/apim-foundry-integration.bicep`: existing-resource semantics keep Stage 2
  separate from foundation mutation; this change does not alter role scopes or deployment order.

## Goals / Non-Goals

**Goals:** deterministic endpoint selection; no built-in client lookup in custom mode;
explicit distinction between direct-private measurement and operator-attested routing.

**Non-Goals:** provision intermediary networks or corporate DNS; relax backend security;
detect arbitrary proxy topology automatically; guarantee no platform dependency uses an
Azure-managed name; change certificate handling or allow overlapping foundation deployments.

## Decisions

### D1: Endpoint mode is separate from ownership

Add `endpointMode` (`built-in` default, `custom`), `endpointAccessPath`
(`direct-private` default, `corporate-routed`), and `customEndpointHostnames`
object with `gateway`, `developerPortal`, `management`. Parameter examples expose
`APIM_ENDPOINT_MODE`, `APIM_ENDPOINT_ACCESS_PATH`, `APIM_CUSTOM_ENDPOINT_HOSTNAMES`.
Normalize lowercase DNS names; reject schemes, ports, paths, wildcard selections, and
missing entries. Corporate-routed is valid only with custom/external. Custom mode uses
external DNS ownership; custom/blueprint fails explicitly rather than creating corporate
zones. Built-in/blueprint and built-in/external stay supported.

This limited matrix avoids inventing workload ownership of corporate DNS. Keep the
existing built-in zone contract for its resource branch, not as a universal endpoint rule.
Do not use hostnameMode to choose endpoints: it controls certificate request assembly.

### D2: Typed endpoints and preserved certificate semantics

Derive a selected endpoint list with roles and a selected gateway URL. Emit additive
`endpointAccess` metadata and mode-aware `privateDnsHandoff`; keep
`apimGatewayHostname` as its existing built-in value for compatibility and add
`selectedGatewayHostname`. Custom handoff lists only the three mandatory endpoints and
names legacy portal/SCM as excluded client checks. It does not delete those platform
features or change Azure infrastructure networking.

Validate selected custom names against effective hostname bindings during foundation
deployment and against live bindings at runtime, including case-insensitive matching
and matching endpoint type. Reuse hostname resolution helpers; do not reimplement PFX
capture. Manual/PFX-managed domains still require resupply on foundation redeploy.

### D3: Two verification paths, no broad IP exception

Direct-private retains current DNS-to-live-VIP equality and certificate-validated HTTPS.
Corporate-routed performs live binding, Internal SKU/posture, DNS, and TLS checks, plus
requires `endpointValidationEvidence` context and network-owner attestation. Root HTTP
responses measure transport, not APIM origin or application success.

`endpointValidationEvidence` extends the required fields of
`specs/00-network-foundation/contracts/validation-evidence.md:8-18`, not just its status enum.
Use these exact JSON field names in inputs, handoffs, documentation, and tests:

| Fields | Contract |
|---|---|
| `validationType` | Required base field; `apim-endpoint-access` identifies this gate. |
| `status` | Required base field; `pass`, `fail`, or `blocked`. Only `pass` can advance readiness. |
| `owner` | Required base field; responsible Azure role, with `network-owner` for corporate routing. |
| `scope` | Required base field; generic deployment scope, not a live Azure resource ID. |
| `approvalReference` | Required base field; generic approval token or note, not a live resource identifier. |
| `evidenceSummary` | Required base field; short redacted summary of checks and disposition. |
| `timestampUtc` | Required base field; ISO-8601 UTC validation-event timestamp. No `timestamp` or `validationTimestamp` alias substitutes for it. |
| `apimServiceId`, `endpointMode`, `endpointAccessPath`, `selectedHostnames` | Required extension fields; intended service ID, mode, access path, and exact `gateway`/`developerPortal`/`management` hostname map. |
| `validationReference` | Required extension field; non-placeholder reference to the retained validation record. |
| `routingApprovalReference` | Required for corporate routing; non-placeholder reference to the network-owner route approval, separate from the generic `approvalReference`. |

All required fields must be present, non-empty, and of the documented type: strings except
the `selectedHostnames` object. Invalid records cannot prove readiness. Runtime validation
checks the ISO-8601 UTC timestamp; Bicep enforces required fields, enums, and context equality,
without claiming to authenticate the timestamp or external approval.
The generic base fields remain redacted. Live context in the extension fields belongs only
in untracked deployment inputs/handoffs and the customer evidence store; committed examples
use generic placeholders, never live context. The referenced network-owner record must identify
the intended Internal APIM upstream and approved client path without unapproved public exposure.

Expose `APIM_ENDPOINT_VALIDATION_EVIDENCE` JSON in parameter files. Structural/equality
checks can enforce context; they cannot authenticate the external record, verify its
author, or detect every route change. Operator approval is explicitly required and
revalidation is required after routing/hostname/certificate/service changes. Do not
present non-empty strings, timestamps, TLS interception trust, or 100.64/10 as proof.
Preserve the standard external-DNS evidence reference for legacy built-in configurations.

### D4: Readiness and integration consistency

Custom readiness requires a complete D3 evidence record matching the generic base contract
and selected context, with explicit `status: pass`.
Missing evidence or required fields, `fail`, `blocked`, and invalid fields cannot produce deployed
readiness; report failed/blocked outcomes explicitly and reject invalid values. Stage 2
rejects non-pass custom handoffs even if a supplied overall readiness says deployed.
Keep DNS readiness pending without passing evidence; retain all other
foundation gates. Bicep records operator evidence, while runtime validation establishes
measured checks; an ARM success is not live proof. Stage 2 takes selected endpoint
metadata from the handoff, checks its service/selection consistency and the selected
live gateway binding, and does not create APIM/DNS/monitoring.

For a legacy handoff without endpoint metadata, accept only built-in/direct-private
selection; reject any custom input without a custom handoff. Default request URLs use
selected gateway and API path. Validate any `APIM_INTEGRATION_REQUEST_URL` override
before using secrets, including HTTPS scheme, host, configured path, and absence
of userinfo. Only implicit port 443 or explicit `:443` is accepted; reject all other ports
before any credential-bearing request. Explicit client settings in future agent work consume the selected URL;
never silently rewrite a Foundry backend endpoint to the APIM hostname.

### D5: Coverage and traceability

All spec references below are relative to this change; each requirement and all of its
scenarios are covered by the named tasks.

| Requirement in `specs/apim-endpoint-access/spec.md` | Decisions | Affected surfaces/modes | Tasks | Acceptance scenarios |
|---|---|---|---|---|
| Explicit endpoint modes | D1, D2 | Foundation Bicep, both parameter files, runtime endpoint selection; built-in/blueprint, built-in/external, custom/external; custom/blueprint rejected | 1.1, 2.1, 2.2, 4.1 | Existing standard configuration; Built-in names are blocked; Incomplete custom configuration; Unsupported custom DNS ownership |
| Live endpoint binding verification | D2, D3 | Effective/live bindings, foundation/all runtime validator | 2.1, 2.2, 4.1 | Valid custom bindings; Wrong service or invalid certificate |
| Access-path-specific verification | D1, D3, D4 | Direct and corporate branches, access-path inputs, evidence validation/readiness | 2.1, 2.2, 4.1, 4.2 | Direct custom access; Approved intermediary; Unproven intermediary |
| Generic endpoint evidence fields | D3, D4 | Evidence JSON inputs/handoffs, runtime schema checks, generic/redacted documentation | 2.1, 2.2, 3.1, 3.2, 4.1 | Conforming generic evidence; Generic evidence contract enforced |
| Deployment endpoint evidence extension | D3, D4 | Customer-store context, DNS/foundation guards, runtime and Stage 2 validation | 2.1, 2.2, 3.1, 3.2, 4.1 | Complete deployment evidence; Invalid deployment evidence |
| Context-bound readiness handoff | D2, D3, D4 | DNS module, foundation outputs, runtime evidence validation, Stage 2 preflight/Bicep | 2.1, 2.2, 3.1, 4.1 | Custom readiness completed; Changed selection or stale evidence; Non-pass validation evidence; Legacy standard handoff |
| Selected gateway integration | D2, D4 | Foundation endpoint selection, integration/all requests, URL output/overrides, inventoried client examples below | 2.1, 2.2, 3.1, 3.2, 4.1, 4.2 | Custom gateway request; Selected endpoint consumers; Conflicting override; Non-default HTTPS port |
| Explicit operational limits | D3, D5 | Chapter 02 spec/plan/tasks/contracts, README, runtime evidence guidance, validation docs, related active artifacts | 1.1, 2.2, 3.2, 4.2 | Custom-only organization |

Affected callers include `foundation`, `integration`, `all`, offline compile/static checks,
runtime checks, foundation handoff consumers, default and overridden integration requests,
and selected gateway output consumers. DNS ownership and endpoint selection are orthogonal
within the allowed matrix. Diagnostics policy/blueprint ownership, Developer/Premium SKU,
Foundry resource scopes, certificate preserve/merge/replace, and cross-stage ownership
remain unchanged. Workspace gateways, v2-tier management, multi-region endpoint mapping,
custom wildcard selection, and provisioning corporate routing are excluded.

Gateway-consumer baseline (paths are repository-relative; task 3.2 owns documentation
updates and task 4.1 verifies consistency, not live execution of future chapter snippets):

| Existing consumers | Required selection behavior / boundary |
|---|---|
| `specs/02-apim-ai-gateway/validation/validate.sh`, `specs/02-apim-ai-gateway/validation/us3-requests.md`, `specs/02-apim-ai-gateway/quickstart.md`, `infra/envs/poc/README.md`, `chapters/02-ai-gateway.md` | Derive smoke-request URLs and operator instructions from the selected gateway; retain configured API paths and existing built-in examples explicitly labeled as such. |
| `chapters/21-foundry-project-blueprint.md`, `chapters/21a-self-service-portal.md` | Populate `APIM_URL`, `apimGatewayUrl`, stored secrets, and onboarding `apimEndpoint` from the selected gateway instead of an unconditional built-in URL. |
| `chapters/13-m365-custom-engine.md`, `chapters/24-developer-build-experience.md`, `chapters/25-cicd-gates.md`, `chapters/26-end-to-end-walkthrough.md`, `chapters/27-developer-journey.md` | Forward selected `APIM_GATEWAY_URL` through model clients, evaluators, onboarding, smoke commands, and CI reports; no built-in fallback in custom configuration. Existing API/model paths remain unchanged. |
| `chapters/04-api-center.md`, `chapters/05-react-discovery-ui.md`, `chapters/07-prompt-agent.md`, `chapters/08-hosted-agent.md`, `chapters/09-work-iq.md`, `chapters/10-serverless-agent.md` | Use the selected gateway for APIM MCP/A2A URLs, `VITE_APIM_URL`, and the serverless client's APIM-routed `AZURE_OPENAI_ENDPOINT`; preserve their route suffixes. Do not rewrite the independent `VITE_API_CENTER_URL` or actual Foundry backend endpoints. |
| `chapters/23-tool-governance.md` | API Center `managementPortalUri` uses the selected developer-portal hostname, not the gateway hostname, in custom examples. |
| `chapters/14-copilot-studio-vnet.md` | Identify URL snippets as separate private-endpoint/Power Platform topology examples, outside this classic Internal-VNet gate; do not claim its DNS resources or live custom-path acceptance are covered by this change. |

Historical validation dispositions, archived changes, and scratch files are not active
gateway consumers and are not rewritten. Future executable agent/portal implementations
remain separate chapter work; this change wires their existing instructional URL handoff,
not their SDK compatibility, topology, or live acceptance.

## Risks / Trade-offs

- Corporate origin cannot be proven from curl alone -> named network-owner approval plus
  live bindings/transport evidence; mark absent evidence BLOCKED.
- Built-in compatibility retains assumptions unsuitable after custom non-gateway bindings ->
  operator must select custom mode; do not silently infer the mode or weaken standard checks.
- Stage 1 updates can alter custom certificate bindings -> keep existing PFX handling and
  inspect what-if; no parallel foundation updates.
- Evidence can become stale without a name change -> mandatory operator revalidation on
  route/certificate changes; no claim of continuous monitoring.
- An operator can falsely label evidence pass -> explicit outcomes prevent accidental
  acceptance of failed/blocked results, not forged evidence; external approval remains trusted.
- Client-access success does not prove private Foundry access -> retain separate model,
  managed-identity, backend routing, request, and telemetry acceptance.

## Migration Plan

Keep old default inputs/outputs working. Add parameters and selected endpoint metadata,
update validator and documentation together, and reconcile related active artifacts in
task 1.1. Custom operators select external/custom plus their approved access path, keep
certificates intact, run checks, record evidence, preview/redeploy foundation, and regenerate
the handoff from that exact deployment before Stage 2. A mode or upstream change invalidates
the evidence. Rollback to built-in requires restoring actual built-in access; it is not
valid where policy blocks those names.

## Readiness Record

User approved three mandatory custom endpoints, legacy portal/SCM client exclusions,
and evidence-backed corporate routing. Implementation changes no live resources. Authoritative
platform feasibility is established for classic APIM custom bindings; external origin
attestation is explicitly not a platform guarantee. Local acceptance task 4.1 is complete;
authorized live customer route/backend evidence remains BLOCKED under task 4.2 and gates
deployment acceptance. The implementation PR remains draft, not deployment-approved.
No customer identifiers or secrets belong in committed artifacts.

Implementation evidence (local, not live): task 1.1 reconciled Chapter 02 and the two active
contracts; `openspec validate support-apim-custom-endpoint-access --strict` passed.
Supplementary strict validation of the related changes reports pre-existing long-requirement
warnings; it does not establish root Chapter 02 correctness. Task 2.1 uses shared
`infra/modules/apim/endpoints.bicep` predicates and the existing certificate assembler.
`bash tests/network/test-apim-endpoints.sh` passed evaluated matrix, hostname, role binding,
and evidence/readiness predicates including every missing/empty/wrong-type field, non-pass,
context mismatch, and timestamp-alias rejection. Foundation/DNS builds and both foundation
parameter builds passed. `bash tests/network/test-apim-hostnames.sh` and
`bash tests/foundry/test-apim-review-regressions.sh` passed. ARM does not validate timestamp
semantics or authenticate approval; runtime timestamp checks and full cross-surface/live
acceptance remain pending. No live resources were changed.

Task 2.2: `bash -n specs/02-apim-ai-gateway/validation/validate.sh tests/foundry/test-apim-endpoint-validation.sh`
and `bash tests/foundry/test-apim-endpoint-validation.sh` passed. The mocks prove three
custom-only probes, all role bindings, Internal classic posture, certificate failure,
direct VIP equality, attested corporate routing, complete valid evidence, every required
missing/empty/wrong-type field, timestamp validity/aliases, mismatches, and non-pass outcomes.
`bash tests/foundry/test-apim-review-regressions.sh` passed again. These are mocked/local
results, not live client or upstream approval.

Task 3.1: evaluated handoff predicates, both integration parameter builds, and
`bash tests/foundry/test-apim-staged-contracts.sh` passed. Extended
`bash tests/foundry/test-apim-endpoint-validation.sh` passed custom/legacy handoffs,
missing/invalid evidence, timestamp/alias rejection, stale selection/live gateway,
and URL scheme/host/path/userinfo/port guards. Invalid URLs were exercised through
the mocked full integration preflight and stopped before downstream reads or
credential-bearing requests. Implicit and explicit 443 passed. Stage 2 remains
existing-resource-only; runtime approved requests must return a chat-completion shape,
not merely a successful HTTP status. Live requests remain task 4.2.

Task 3.2: `bash tests/foundry/test-apim-endpoint-docs.sh` passed the full D5 consumer
inventory, selected gateway/developer portal handoffs, preserved model/MCP/A2A routes,
independent API Center/Foundry URLs, and explicit Chapter 14 exclusion. Operator guidance
and redacted foundation evidence templates enumerate every exact base/extension field;
integration consumes the same retained endpoint evidence. JSON snippets are explicitly
rendered templates, not claims of automatic environment interpolation. The confidentiality
scan of changed/new files and `git diff --check` passed. During cross-surface review DNS
resource conditions were also bound to the module's selection/evidence guards, preventing
invalid custom/blueprint writes; the coupled compiled regression passed.

Task 4.1: reviewed the complete tracked diff and new helper/tests against D5, including
both entry points and parameter pairs, DNS ownership branches, effective/live role bindings,
evidence shapes/outcomes, all selected URL consumers, and unchanged private Foundry boundaries.
On the final coherent revision the following local commands passed:

- `OFFLINE_ONLY=true specs/02-apim-ai-gateway/validation/validate.sh all`
- `bash tests/foundry/test-apim-staged-contracts.sh`
- `bash tests/foundry/test-apim-review-regressions.sh`
- `bash tests/foundry/test-apim-hostname-capture.sh`
- `bash tests/network/test-apim-hostnames.sh`
- `bash tests/network/test-apim-endpoints.sh`
- `bash tests/foundry/test-apim-endpoint-validation.sh`
- `bash tests/foundry/test-apim-endpoint-docs.sh`
- `bash -n specs/02-apim-ai-gateway/validation/validate.sh tests/foundry/test-apim-endpoint-validation.sh tests/foundry/test-apim-endpoint-docs.sh tests/network/test-apim-endpoints.sh`
- `openspec validate support-apim-custom-endpoint-access --strict`
- `git diff --check`
- `bash scripts/network/scan-confidentiality.sh` with all modified and new task files as arguments.

Offline all-mode compiled both entry points, their four parameter files, and owned modules.
Only pre-existing `prefer-interpolation` warnings in `api.bicep` and `backend.bicep` remain.
The ownership check now inspects actual resource writes recursively, allowing the compiler's
explicit `existing: true` APIM reference while rejecting seeded nested foundation writes.
Evaluated parameter cases verify custom declaration/certificate JSON in both foundation
files and preserved customer-example defaults/individual PFX inputs. Both files now use
environment-backed assignments; certificate mode semantics are unchanged. The ignored local
parameter file was adjusted with user authorization and remains untracked. Mocked direct
checks reject a non-VIP secondary DNS address and accept multiple reported private VIPs.
Compilation, structural checks, evaluated predicates, and mocks are not Azure live proof.
OpenSpec validation covers this delta, not semantic validation of root Chapter 02 specs.

Task 4.2: **BLOCKED**. No authorized live environment, current network-owner routing record,
foundation what-if/runtime evidence, exact-deployment endpoint handoff, or Stage 2 preview,
model/telemetry/private Foundry/managed-identity evidence was supplied. Both standard/direct
and custom approved-path acceptance (including unavailable built-in client names) remain
mandatory. No live deployment was attempted, and no live evidence is claimed. Keep #104
open and task 4.2 unchecked; do not archive or approve deployment on local results alone.
