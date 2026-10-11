# Stage 2 Foundry Integration Runtime Evidence

**Current status:** BLOCKED

Required live evidence:

- selected Stage 1 `endpointAccess` context and live gateway binding, with complete matching
  pass custom endpoint evidence; overall deployed readiness does not override non-pass evidence;
- APIM identity discovery and exactly one account-scoped `Cognitive Services OpenAI User`
  assignment;
- approved/private Foundry account and deployed allowlisted model;
- HTTPS backend with managed-identity authentication;
- approved-model named value, subscription-protected API, product, and policies;
- authorized requests reach the mapped deployment;
- unsupported models and unauthenticated requests fail before Foundry;
- telemetry is attributable without credentials, prompts, or completions.

Use `APIM_GATEWAY_URL` from the handoff's `selectedGatewayUrl`. Preserve the configured API path;
request overrides require HTTPS, selected host/path, no userinfo/query/fragment, implicit/explicit
443 before credentials. A model call must return a chat completion, not just HTTP 2xx.
The exact generic/extension evidence fields, UTC `timestampUtc` validation, and redaction rules
are in [`README.md`](README.md#selected-endpoint-validation). Legacy metadata-free handoffs
are built-in/direct-private only. Client DNS/TLS does not prove private Foundry authorization.

The endpoint evidence template is in [`foundation-runtime.md`](foundation-runtime.md):
Stage 2 consumes that same retained record in the exact deployment's
`APIM_STAGE1_ENDPOINT_ACCESS.endpointValidationEvidence`; do not invent a separate pass
record to bypass a failed/blocked foundation gate. Actual model/private-backend/identity and
telemetry evidence is recorded independently here.

Run after deployment with authorized client and telemetry inputs:

```bash
APIM_VALIDATE_INTEGRATION_REQUESTS=true \
  specs/02-apim-ai-gateway/validation/validate.sh integration
```
