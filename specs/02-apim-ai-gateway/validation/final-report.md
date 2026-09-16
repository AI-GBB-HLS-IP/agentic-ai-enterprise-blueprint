# Chapter 02 Staged Validation Report

| Stage | Offline status | Live status | Readiness |
|---|---|---|---|
| APIM foundation | PASS | BLOCKED: approved customer values, what-if, deployment/runtime, internal reachability | Not yet evidenced live |
| Foundry integration | PASS | BLOCKED: GenAI approval/account enablement, approved Foundry/model, what-if, deployment/request/telemetry | Not deployed/evidenced |

## Offline Evidence

- Every APIM module and both environment entry points compile.
- Foundation parameters and compiled resources contain no Foundry/model/backend/API/product/token
  dependency.
- Integration references existing APIM and declares no foundation-owned resource.
- Customer subnet assertions, APIM public IP association, Premium/internal/TLS settings,
  AllLogs/AllMetrics handling, and capacity alert are present.
- Static ownership checks pass and their seeded-regression self-tests fail as expected.
- `OFFLINE_ONLY=true validation/validate.sh all` passes.

## Live Blockers

See `foundation-preview.md`, `foundation-runtime.md`, `integration-preview.md`,
`integration-runtime.md`, and `idempotency.md`. Historical combined evidence does not satisfy the
new staged acceptance criteria.
