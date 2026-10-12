# Historical Partial Integration Evidence — Requests (T032)

> This predates the staged integration entry point and remains incomplete. See
> `integration-runtime.md`.

Status: **PARTIAL PASS (request behavior passed; rejected-call backend correlation pending)**

Validation date: 2026-08-27

## Live result

Tests were executed from `vm-fnd-jbox` against the private APIM hostname:

```text
DNS: 10.0.1.4
No subscription key: HTTP 401
Approved model: HTTP 200, response model gpt-4.1-mini-2025-04-14
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

The historical results above are unchanged. Current reproduction uses the selected gateway
from the validated handoff, not a built-in fallback; Stage 2 preflight validates any override.

```bash
export APIM_GATEWAY_URL="$(jq -er '.selectedGatewayUrl' <<<"$APIM_STAGE1_ENDPOINT_ACCESS")"
APIM_REQUEST_URL="${APIM_GATEWAY_URL}/${APIM_GOVERNED_API_PATH:-llm/v1}/chat/completions"
for i in $(seq 1 10); do
  curl -sS -o /tmp/apim-ok-$i.json -w "%{http_code}\n" \
    "$APIM_REQUEST_URL" \
    -H "Content-Type: application/json" \
    -H "Ocp-Apim-Subscription-Key: <valid-key>" \
    -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hello"}],"stream":false}'
done

curl -sS -o /tmp/apim-deny.json -w "%{http_code}\n" \
  "$APIM_REQUEST_URL" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hello"}],"stream":false}'

curl -sS -o /tmp/apim-unapproved.json -w "%{http_code}\n" \
  "$APIM_REQUEST_URL" \
  -H "Content-Type: application/json" \
  -H "Ocp-Apim-Subscription-Key: <valid-key>" \
  -d '{"model":"gpt-4.1","messages":[{"role":"user","content":"hello"}],"stream":false}'
```

## Pass criteria

- At least 9/10 valid requests return success.
- 100% of unauthenticated requests are rejected by APIM (401/403).
- Rejected request has no corresponding Foundry backend call.
