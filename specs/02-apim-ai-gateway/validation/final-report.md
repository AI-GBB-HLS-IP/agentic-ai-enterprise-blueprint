# Chapter 02 Staged Validation Report

| Stage | Offline status | Live status | Readiness |
|---|---|---|---|
| APIM foundation | PASS | PASS: accepted 2026-09-16 | Deployment and private-path runtime validated |
| Foundry integration | PASS | BLOCKED: customer Foundry approval and an approved private model deployment | Pending live what-if, deployment, request, and telemetry evidence |

## Offline Evidence

- Every APIM module and both environment entry points compile.
- Foundation parameters and compiled resources contain no Foundry/model/backend/API/product/token
  dependency.
- Integration references existing APIM and declares no foundation-owned resource.
- Customer subnet assertions, APIM public IP association, Premium/internal/TLS settings,
  AllLogs/AllMetrics handling, and capacity alert are present.
- Static ownership checks pass and their seeded-regression self-tests fail as expected.
- `OFFLINE_ONLY=true validation/validate.sh all` passes.

## Stage 1 Live Evidence

Issue #71 records the authoritative redacted acceptance evidence from an authorized customer Azure
environment on 2026-09-16:

- Deployment validation passed.
- The what-if was reviewed as non-disruptive, with no resource replacement or deletion.
- The unchanged-input preview and idempotency check passed.
- The deployment succeeded.
- APIM ran at Developer capacity one in internal VNet mode.
- The private-path Echo API smoke test returned HTTP 200.

Customer identifiers, subscription keys, and other secrets are intentionally omitted.

## Stage 2 Blocker

Foundry integration remains blocked pending customer Foundry approval and an approved private model
deployment. Its live what-if, unchanged-input/idempotency check, deployment, authorized model
request, and telemetry acceptance remain pending.
