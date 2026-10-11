# Stage 1 Foundation Runtime Evidence

**Current status:** BLOCKED

Supported Stage 1 tiers:

- **Developer, capacity 1** — supported for smoke testing and recorded acceptance evidence.
- **Premium** — supported for production deployments.

Developer capacity 1 is intentional smoke-test evidence and is compliant with the Stage 1
contract; it must not be described as a production-tier deployment.

Required live evidence:

- customer subnet controls and active route-table profile;
- internal APIM and system identity using the selected supported tier;
- approved classic platform public IP;
- five built-in endpoint records/checks by default, or the three selected custom
  Proxy/DeveloperPortal/Management bindings with external DNS and no built-in probes;
- direct-private resolution to live VIPs and TLS, or measured custom DNS/TLS plus retained
  network-owner approval of the intended Internal APIM upstream and corporate client path;
- complete matching pass endpoint evidence and handoff from the exact deployed foundation;
- TLS and weak-protocol settings;
- AllLogs/AllMetrics diagnostic destination, including policy-owned settings;
- average capacity alert threshold of at least 60 percent.

Run from the authorized environment:

```bash
VALIDATION_PHASE=runtime \
RUN_WHAT_IF=false \
APIM_VALIDATE_ENDPOINT_REACHABILITY=true \
  specs/02-apim-ai-gateway/validation/validate.sh foundation
```

No Foundry resource is required for this evidence.
See [`stage1-smoke-test.md`](stage1-smoke-test.md) for prerequisites, deployment, expected checks,
and the evidence return format.

Custom evidence extends the generic contract with all seven exact base fields, including
ISO-8601 UTC `timestampUtc`, and all deployment extension fields documented in
[`README.md`](README.md#selected-endpoint-validation). Keep base fields redacted and live
extension context untracked. Missing/invalid/non-pass evidence cannot advance custom readiness.
Legacy portal/SCM client exclusions do not remove platform dependencies. HTTP root success
is transport, not origin/model proof; separate Foundry acceptance remains required.

Redacted corporate evidence template (placeholders are intentionally not deployment-ready):

```json
{
  "validationType": "apim-endpoint-access",
  "status": "blocked",
  "owner": "network-owner",
  "scope": "apim-foundation",
  "approvalReference": "approval-generic-001",
  "evidenceSummary": "Authorized endpoint and routing validation pending.",
  "timestampUtc": "2026-10-11T00:00:00Z",
  "apimServiceId": "<selected-apim-service-id>",
  "endpointMode": "custom",
  "endpointAccessPath": "corporate-routed",
  "selectedHostnames": {
    "gateway": "api.example.com",
    "developerPortal": "developer.example.com",
    "management": "management.example.com"
  },
  "validationReference": "<retained-validation-record>",
  "routingApprovalReference": "<network-owner-route-approval>"
}
```
