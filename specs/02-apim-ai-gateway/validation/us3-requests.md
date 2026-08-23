# US3 request behavior evidence (T032)

Status: **BLOCKED (live Azure gate unresolved)**

## Test matrix

1. Ten valid requests from private client with APIM subscription key.
2. One invalid/unauthenticated request without APIM subscription key.

## Commands to run

```bash
for i in $(seq 1 10); do
  curl -sS -o /tmp/apim-ok-$i.json -w "%{http_code}\n" \
    "https://apim-agent-factory-poc.azure-api.net/llm/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Ocp-Apim-Subscription-Key: <valid-key>" \
    -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hello"}],"stream":false}'
done

curl -sS -o /tmp/apim-deny.json -w "%{http_code}\n" \
  "https://apim-agent-factory-poc.azure-api.net/llm/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hello"}],"stream":false}'
```

## Pass criteria

- At least 9/10 valid requests return success.
- 100% of unauthenticated requests are rejected by APIM (401/403).
- Rejected request has no corresponding Foundry backend call.
