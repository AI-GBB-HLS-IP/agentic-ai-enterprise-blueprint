# Chapter 02 validation evidence

This directory stores deterministic validation artifacts for the APIM AI Gateway core increment.
It intentionally separates:

1. **Offline-deterministic checks** (file presence + Bicep compile + static scope guardrails).
2. **Live Azure read-only gates** (provider/schema confirmation, prerequisite inspection, what-if,
   DNS and runtime request tests).

Run from repository root:

```bash
./specs/02-apim-ai-gateway/validation/validate.sh
```

## Gate policy

- If offline checks fail, implementation is invalid and must be fixed before merge.
- If live checks are blocked (no Azure login/permissions), artifacts must record **BLOCKED**
  status rather than claiming pass/fail.
- Deployment approval remains blocked until all mandatory live gates in `api-confirmation.md` and
  `prerequisites.md` are resolved.

## Evidence files

- `api-confirmation.md` — T005-T007 provider/schema/workspace confirmation.
- `prerequisites.md` — T008-T011 resource prerequisite and subnet readiness checks.
- `us1-what-if.md`, `us1-gateway.md` — User Story 1 what-if + network posture evidence.
- `us2-identity-dns.md` — User Story 2 identity scope + private DNS evidence.
- `us3-what-if.md`, `us3-requests.md`, `us3-observability.md` — User Story 3 API governance evidence.
- `idempotency.md` — second what-if comparison evidence.
- `final-report.md` — consolidated readiness summary and blockers.

## Scope boundary assertions

- No MCP server resources and no A2A APIs are declared in this increment.
- No fallback public endpoint path is declared (`virtualNetworkType: Internal` + private DNS).
- No API key/secret-based backend authentication is declared; managed identity only.
- No secondary backend, Content Safety resource, or semantic cache is declared.

## Ownership boundaries

- **Platform engineering-owned** in this increment:
  - `infra/modules/apim/*.bicep`
  - `infra/envs/poc/apim.bicep`
  - `infra/envs/poc/apim.bicepparam`
  - validation runner/evidence in this directory
- **Unchanged by this increment**:
  - `infra/modules/network/*` (except consuming existing `snet-apim` through composition)
  - `infra/modules/foundry/*`

## No-secret invariant

- Backend authentication is enforced through `authentication-managed-identity`.
- APIM-to-Foundry authorization uses the `Cognitive Services OpenAI User` role assignment.
- No Foundry API key, Key Vault secret lookup, named value secret, or connection string is
  declared in APIM backend configuration.

## Module I/O coverage summary

- `main.bicep`: APIM identity/network core + role assignment + readiness object.
- `main.bicep`: classic Premium VNet injection and subnet readiness outputs.
- `private-dns.bicep`: `azure-api.net` zone/link/record outputs and DNS readiness state.
- `backend.bicep`: Foundry backend + managed-identity policy snippet output.
- `api.bicep`: single `chat/completions` API + product/policy + scope-boundary outputs.
- `observability.bicep`: Application Insights/Log Analytics/logger/diagnostic outputs.
