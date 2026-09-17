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
