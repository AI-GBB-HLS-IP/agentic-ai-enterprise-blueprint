# Chapter 02 Validation

Run one explicit mode:

```bash
specs/02-apim-ai-gateway/validation/validate.sh foundation
specs/02-apim-ai-gateway/validation/validate.sh integration
specs/02-apim-ai-gateway/validation/validate.sh all
```

Set `OFFLINE_ONLY=true` for compilation and static regression checks without Azure reads. A normal
run performs safe read-only checks and what-if when the required environment values are present.
Exit code `3` means offline checks passed but one or more live gates are blocked.

Use `VALIDATION_PHASE=preview` for pre-deployment prerequisite checks and what-if without runtime
resource checks. Use `VALIDATION_PHASE=runtime` after deployment to skip what-if and inspect the
deployed stage. The default `all` performs both.

Customer Stage 1 operators should follow [`stage1-smoke-test.md`](stage1-smoke-test.md).

## Evidence Paths

| Stage | Preview | Runtime |
|---|---|---|
| APIM foundation | `foundation-preview.md` | `foundation-runtime.md` |
| Foundry integration | `integration-preview.md` | `integration-runtime.md` |
| Both | `idempotency.md` | `final-report.md` |

Foundation readiness does not depend on integration. Foundation mode contains no Cognitive
Services command or Foundry resource check. Integration mode begins by resolving the existing
APIM identity, then evaluates Foundry governance and integration resources.

## Required Live Environment Values

Foundation:

- `APIM_RESOURCE_GROUP`, `APIM_NETWORK_RESOURCE_GROUP`, `APIM_VNET_NAME`, `APIM_SUBNET_NAME`
- `APIM_APPROVED_NSG_RESOURCE_ID`
- `APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID` or `APIM_ROUTE_TABLE_EXCEPTION_REFERENCE`
- `APIM_SUBNET_NAMING_EXCEPTION_REFERENCE` when the name is not `apimsubnet-*`
- `APIM_PUBLISHER_EMAIL`
- `APIM_LOG_ANALYTICS_WORKSPACE_ID`
- `APIM_EXTERNAL_DNS_VALIDATION_REFERENCE` after live validation when customer-managed DNS owns
  APIM private endpoint resolution
- `APIM_POLICY_DIAGNOSTICS_VALIDATION_REFERENCE` after live validation when Azure Policy owns
  the diagnostic setting
- optionally `APIM_FOUNDATION_PARAMETERS_FILE` (preferred) or `FOUNDATION_PARAMETERS` to select
  a non-default Stage 1 parameter file

Integration:

- existing APIM and Foundry resource group/name/ID values;
- `APIM_STAGE1_SERVICE_ID` and `APIM_STAGE1_FOUNDATION_READINESS` copied from the validated Stage 1
  deployment outputs;
- `GENAI_APPROVAL_REFERENCE`, `FOUNDRY_ENABLEMENT_REFERENCE`,
  `FOUNDRY_CUSTOMER_POLICY_SOURCE`;
- `FOUNDRY_APPROVED_REGIONS` as a required non-empty JSON array with no repository fallback;
- `FOUNDRY_APPROVED_MODELS` as a JSON array, for example
  `[{"publicName":"gpt-4.1-mini","deploymentName":"gpt-4.1-mini","enabled":true}]`.

Use `APIM_VALIDATE_ENDPOINT_REACHABILITY=true` only from an authorized internal network. Use
`APIM_VALIDATE_INTEGRATION_REQUESTS=true` only when authorized request and telemetry inputs are
available.

## Historical Files

`us1-what-if.md`, `us1-gateway.md`, `us2-identity-dns.md`, `us3-what-if.md`,
`us3-requests.md`, and `us3-observability.md` describe the legacy combined deployment. They are
retained for traceability and cannot establish current staged readiness.
