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
- `APIM_EXTERNAL_DNS_VALIDATION_REFERENCE` after live validation for built-in/external DNS;
  leave it empty for custom mode
- `APIM_POLICY_DIAGNOSTICS_VALIDATION_REFERENCE` after live validation when Azure Policy owns
  the diagnostic setting
- optionally `APIM_FOUNDATION_PARAMETERS_FILE` (preferred) or `FOUNDATION_PARAMETERS` to select
  a non-default Stage 1 parameter file
- optional independent JSON tag objects: `APIM_SERVICE_TAGS`, `APIM_PUBLIC_IP_TAGS`,
  `APIM_LOG_ANALYTICS_WORKSPACE_TAGS`, `APIM_APP_INSIGHTS_TAGS`,
  `APIM_CAPACITY_ALERT_TAGS`, `APIM_PRIVATE_DNS_ZONE_TAGS`, and
  `APIM_PRIVATE_DNS_VNET_LINK_TAGS`; new inputs default to `{}`, while the public IP always
  enforces `ProjectCode: APIM`

Integration:

- existing APIM and Foundry resource group/name/ID values;
- `APIM_STAGE1_SERVICE_ID` and `APIM_STAGE1_FOUNDATION_READINESS` copied from the validated Stage 1
  deployment outputs;
- `APIM_STAGE1_ENDPOINT_ACCESS` copied from that exact deployment's `endpointAccess`, with
  the same endpoint mode/access path/custom hostname inputs; legacy empty metadata permits
  built-in/direct-private only;
- `GENAI_APPROVAL_REFERENCE`, `FOUNDRY_ENABLEMENT_REFERENCE`,
  `FOUNDRY_CUSTOMER_POLICY_SOURCE`;
- `FOUNDRY_APPROVED_REGIONS` as a required non-empty JSON array with no repository fallback;
- `FOUNDRY_APPROVED_MODELS` as a JSON array, for example
  `[{"publicName":"gpt-4.1-mini","deploymentName":"gpt-4.1-mini","enabled":true}]`.

Use `APIM_VALIDATE_ENDPOINT_REACHABILITY=true` only from an authorized internal network. Use
`APIM_VALIDATE_INTEGRATION_REQUESTS=true` only when authorized request and telemetry inputs are
available.

## Selected Endpoint Validation

`APIM_ENDPOINT_MODE` defaults to `built-in`, with `APIM_ENDPOINT_ACCESS_PATH=direct-private`.
Both DNS owners remain supported. Custom requires `APIM_PRIVATE_DNS_MODE=external` and
`APIM_CUSTOM_ENDPOINT_HOSTNAMES` JSON containing exactly gateway, developerPortal, management.
Names must match live Proxy/DeveloperPortal/Management bindings on classic Internal APIM.
Custom performs no built-in probes and excludes only legacy portal/SCM client checks;
platform network dependencies are unchanged.

Direct-private measures every resolved IPv4 against live APIM private IPs and validates
HTTPS certificates. Corporate-routed is custom-only: DNS/TLS are measured, while intended
upstream/route identity is network-owner attestation. An HTTP root response is transport,
not an application/model result or proof of APIM origin. No IP-range approval heuristic
or certificate bypass is used.

Set `APIM_ENDPOINT_VALIDATION_EVIDENCE` to a JSON object extending the generic contract at
`specs/00-network-foundation/contracts/validation-evidence.md`:

| Field | Required contract |
|---|---|
| `validationType` | Non-empty string, exactly `apim-endpoint-access` |
| `status` | `pass`, `fail`, or `blocked`; only pass advances custom readiness |
| `owner` | Responsible Azure role; corporate-routed requires `network-owner` |
| `scope` | Non-empty generic deployment scope |
| `approvalReference` | Non-empty generic/redacted approval token or note |
| `evidenceSummary` | Non-empty redacted disposition |
| `timestampUtc` | ISO-8601 UTC event timestamp, e.g. `2026-10-11T00:00:00Z`; fractional seconds accepted, aliases rejected |
| `apimServiceId` | Non-empty string matching the intended live APIM ID |
| `endpointMode` | Exactly `custom` |
| `endpointAccessPath` | Matching `direct-private` or `corporate-routed` |
| `selectedHostnames` | Exact normalized three-role hostname map matching selection |
| `validationReference` | Non-empty, non-placeholder retained validation record reference |
| `routingApprovalReference` | Corporate-only non-empty, non-placeholder retained network-owner route approval |

Base fields stay generic/redacted. Live extension context is kept only in ignored deployment
inputs/handoffs and customer-approved evidence storage; use generic placeholders in commits.
The redacted JSON shape is in `infra/envs/poc/README.md`. The retained routing record must name
the intended Internal APIM upstream and approved path without unapproved public exposure.
Runtime checks timestamp validity and context; it cannot authenticate an external record or
continuously detect route changes. Revalidate after service/route/hostname/certificate changes.

Missing evidence or live resource/network access is BLOCKED; mismatch, invalid fields,
DNS, or TLS failure is an explicit failure. Passing measured checks cannot override fail/blocked
evidence. Preview/ARM success is not runtime proof. Retain manual PFX resupply on foundation
redeployment and all independent Foundry private connectivity, identity, request, and telemetry
gates. Run CLI and validator in the same environment; WSL variables do not automatically reach
Windows CLI processes, and environment forwarding must not print secrets.

Stage 2 validates complete matching pass custom evidence even if overall readiness says
deployed, plus the live selected Proxy binding. It never redeploys APIM/DNS/monitoring.
Request URLs default to the selected gateway plus configured API path and `/chat/completions`;
overrides are checked before credentials for HTTPS, exact host/path, no userinfo/query/fragment,
and implicit/explicit 443. Model responses require a chat-completion shape and the existing
9/10 reliability threshold, with separate managed-identity/private backend/telemetry gates.

## Historical Files

`us1-what-if.md`, `us1-gateway.md`, `us2-identity-dns.md`, `us3-what-if.md`,
`us3-requests.md`, and `us3-observability.md` describe the legacy combined deployment. They are
retained for traceability and cannot establish current staged readiness.
