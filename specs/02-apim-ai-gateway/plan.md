# Implementation Plan: Staged APIM AI Gateway

## Scope and Sequence

1. Refactor `infra/modules/apim/main.bicep` into an APIM-only module.
2. Refactor `infra/envs/poc/apim.bicep` and `.bicepparam` into the Stage 1 composition.
3. Extend foundation observability and customer policy validation.
4. Add `apim-foundry-integration.bicep` and `.bicepparam` for Stage 2.
5. Split validation, evidence, and operator guidance.
6. Compile all APIM modules and both entry points; run offline validation.
7. Run stage-specific Azure previews and runtime checks only when credentials, permissions,
   customer evidence, and real parameter values are available.

## Resource Ownership

| Resource or control | Stage 1 foundation | Stage 2 integration |
|---|---:|---:|
| Existing VNet/subnet validation | Verify | Read-only posture check |
| APIM service and system identity | Deploy | Existing reference |
| Classic APIM public IP association | Deploy/reference | No access |
| Private DNS zone/link/A records | Deploy | No access |
| Application Insights and Log Analytics | Deploy/reference | No access |
| AllLogs/AllMetrics diagnostics | Deploy or verify policy-owned | No access |
| Capacity alert | Deploy | No access |
| Foundry role assignment | No access | Deploy at account scope |
| APIM backend and model mapping | No access | Deploy |
| Governed API/product/policies | No access | Deploy |

## Stage 1 Design

`infra/modules/apim/main.bicep` receives the approved public IP ID and APIM subnet ID and deploys
only `Microsoft.ApiManagement/service`. Its security configuration is explicit and statically
testable. It outputs identity, private IPs, network mode, and readiness without Foundry fields.

`infra/envs/poc/apim.bicep` references the existing VNet/subnet, performs fail-closed deployment
time assertions for the declared customer policy profile, and composes:

- `modules/apim/main.bicep`
- `modules/apim/private-dns.bicep`
- `modules/apim/observability.bicep`

The parameter file carries policy evidence as non-secret identifiers. Route-table exception
evidence is required when no route table is expected. Policy-owned diagnostics are selected with
an explicit ownership mode and are verified by live validation rather than overwritten.

## Stage 2 Design

### Endpoint selection continuation (#104)

`../../openspec/changes/support-apim-custom-endpoint-access/design.md` D1-D5 is the
endpoint-access design and coverage baseline. Its requirement/scenario-to-task matrix owns
all endpoint acceptance; the staged deployment ownership table above remains unchanged.
Task 1.1 reconciles contracts, 2.1 owns foundation/effective bindings/DNS/evidence,
2.2 owns live binding and path-specific runtime checks, 3.1 owns Stage 2 handoff and
credential-safe URL selection, 3.2 owns every D5 documentation consumer, 4.1 owns local
cross-surface evaluation, and 4.2 owns authorized live deployment acceptance.

Supported selections are built-in/direct-private with either DNS owner, and custom/external
with direct-private or evidence-backed corporate routing. Defaults remain built-in,
direct-private; custom/blueprint and built-in/corporate are rejected. Custom uses three
mandatory roles, excluding only legacy portal/SCM client checks. Certificate modes and
manual PFX resupply are unchanged. Additive selected metadata retains the built-in output.

Custom DNS readiness requires all exact generic and deployment-extension evidence fields
with context equality and explicit pass; missing evidence is pending, non-pass cannot advance,
and invalid fields are rejected. Runtime validates ISO-8601 UTC `timestampUtc`; ARM structure
does not authenticate external approval. Stage 2 verifies this metadata and the live gateway,
accepts legacy handoffs only for built-in/direct-private, and validates HTTPS host/path/443
before using request credentials. Corporate approval is operator attestation, not an IP-range
or HTTP-status inference. Separate Foundry connectivity and telemetry remain mandatory.

Feasibility: existing `infra/modules/apim/hostnames.bicep` assembles effective bindings;
Stage 2's existing-resource reference preserves create/update boundaries. Microsoft Learn
[custom domains](https://learn.microsoft.com/en-us/azure/api-management/configure-custom-domain)
documents replacement of non-gateway defaults and retention of the default gateway;
[Internal VNet](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet)
requires operator DNS. Corporate route provisioning, v2/workspace/multi-region mapping,
wildcard selections, and Chapter 14 topology are excluded. Implementation/live outcomes
must be recorded separately; no task or compilation status proves live readiness.

`infra/envs/poc/apim-foundry-integration.bicep` declares APIM as an existing resource at
`resourceGroup(apimResourceGroupName)`. It derives the system principal directly and composes:

- `modules/apim/foundry-role-assignment.bicep` at the Foundry resource group;
- `modules/apim/backend.bicep` at the APIM resource group;
- `modules/apim/api.bicep` at the APIM resource group.

The integration template contains no APIM service declaration and invokes no private DNS or
observability module. Governance evidence parameters are validated before resource expressions
are used.

## Validation Design

`specs/02-apim-ai-gateway/validation/validate.sh` accepts `foundation`, `integration`, or `all`.
Each mode has:

- file and Bicep compilation checks;
- static ownership regression checks;
- live read-only prerequisites when Azure authentication is available;
- a stage-specific what-if when all required parameter values resolve;
- stage-specific runtime checks when resources exist.

The validator exits nonzero for a failed check and uses exit code 3 for blocked live gates after
offline checks pass. Foundation mode never references Cognitive Services commands or variables.

Static checks inspect compiled ARM resources, not only source text. A seeded Foundry reference in
foundation or a foundation-owned resource in integration must fail.

## Evidence and Reporting

Evidence is grouped as:

- `foundation-preview.md`, `foundation-runtime.md`
- `integration-preview.md`, `integration-runtime.md`
- `idempotency.md`
- `final-report.md`

Historical combined evidence remains clearly labeled and cannot establish current readiness.
`final-report.md` reports foundation and integration statuses separately.

## Rollback

- Stage 2 can be removed without replacing APIM or changing foundation networking, DNS, or
  monitoring.
- Stage 1 recovery is managed separately and does not delete Foundry.
- No template performs automatic cross-stage rollback.
