# Staged Idempotency Evidence

| Check | Status | Required evidence |
|---|---|---|
| Foundation repeated preview | BLOCKED | Two unchanged Stage 1 what-if results with no duplicate/unexpected APIM, identity, DNS, or monitoring changes |
| Integration repeated preview | BLOCKED | Two unchanged Stage 2 what-if results with no duplicate/unexpected role, backend, model, API, product, or policy changes |
| Stage 2 non-disruption | BLOCKED | Integration preview contains no replacement or update of APIM, VNet injection, private DNS, or monitoring |

Offline compiled-template ownership checks pass, but they do not prove Azure idempotency.
