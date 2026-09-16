# Stage 2 Foundry Integration Preview Evidence

**Current status:** BLOCKED  
**Offline template boundary:** PASS

The integration entry point compiles and contains only the Foundry account-scoped role assignment
and APIM backend, approved-model named value, API, operation, product, binding, and policies. APIM
is an existing reference; the template declares no APIM service, private DNS, workspace,
Application Insights, diagnostic setting, or metric alert.

Live what-if requires a validated APIM foundation, actual Foundry identifiers, GenAI approval,
account-enablement evidence, maintained customer policy reference, private Foundry posture, and an
approved deployed model.

```bash
RUN_WHAT_IF=true specs/02-apim-ai-gateway/validation/validate.sh integration
```
