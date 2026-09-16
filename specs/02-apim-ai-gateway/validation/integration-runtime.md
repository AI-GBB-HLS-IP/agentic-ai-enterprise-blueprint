# Stage 2 Foundry Integration Runtime Evidence

**Current status:** BLOCKED

Required live evidence:

- APIM identity discovery and exactly one account-scoped `Cognitive Services OpenAI User`
  assignment;
- approved/private Foundry account and deployed allowlisted model;
- HTTPS backend with managed-identity authentication;
- approved-model named value, subscription-protected API, product, and policies;
- authorized requests reach the mapped deployment;
- unsupported models and unauthenticated requests fail before Foundry;
- telemetry is attributable without credentials, prompts, or completions.

Run after deployment with authorized client and telemetry inputs:

```bash
APIM_VALIDATE_INTEGRATION_REQUESTS=true \
  specs/02-apim-ai-gateway/validation/validate.sh integration
```
