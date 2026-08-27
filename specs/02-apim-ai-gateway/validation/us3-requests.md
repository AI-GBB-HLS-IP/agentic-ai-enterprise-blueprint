# US3 request behavior evidence (T032)

Status: **PARTIAL PASS (request behavior passed; rejected-call backend correlation pending)**

Validation date: 2026-08-27

## Live result

Tests were executed from `vm-fnd-jbox` against the private APIM hostname:

```text
DNS: 10.0.1.4
No subscription key: HTTP 401
Approved model: HTTP 200, model gpt-4.1-mini-2025-04-14
Unapproved model: HTTP 400, error code unsupported_model
Approved-model reliability: 10/10 HTTP 200
```

The success threshold and APIM rejection behavior passed. Correlation against Foundry telemetry
to prove that the unauthenticated request generated no backend call remains pending, so T032 is
not yet complete.

## Test matrix

1. Ten valid requests from private client with APIM subscription key.
2. One invalid/unauthenticated request without APIM subscription key.
3. One request with a valid subscription key but an unapproved model name (expect HTTP 400 with `unsupported_model`).
## Reproduction commands

```bash
for i in $(seq 1 10); do
  curl -sS -o /tmp/apim-ok-$i.json -w "%{http_code}\n" \
    "https://apim-agent-factory-private-poc.azure-api.net/llm/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Ocp-Apim-Subscription-Key: <valid-key>" \
    -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hello"}],"stream":false}'
done

curl -sS -o /tmp/apim-deny.json -w "%{http_code}\n" \
  "https://apim-agent-factory-private-poc.azure-api.net/llm/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hello"}],"stream":false}'
```

## Pass criteria

- At least 9/10 valid requests return success.
- 100% of unauthenticated requests are rejected by APIM (401/403).
- Rejected request has no corresponding Foundry backend call.
