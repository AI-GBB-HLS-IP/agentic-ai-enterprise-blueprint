# Stage 1 Foundation Preview Evidence

**Current status:** BLOCKED  
**Offline template boundary:** PASS

The foundation entry point compiles and its ARM template contains APIM, private DNS, Application
Insights/Log Analytics, diagnostics handling, and a capacity alert. It contains no Cognitive
Services lookup, Foundry role assignment, backend, model mapping, product, or governed API.

Live what-if requires actual values for the APIM resource group, approved corporate publisher,
approved NSG, route-table or exception reference, subnet naming exception where applicable, and
customer-approved public-IP naming, DNS-label, and tag values.

```bash
VALIDATION_PHASE=preview \
RUN_WHAT_IF=true \
  specs/02-apim-ai-gateway/validation/validate.sh foundation
```

Do not change this status until the command succeeds and the resource list is attached.
See [`stage1-smoke-test.md`](stage1-smoke-test.md) for the exact customer handoff.
