# Stage 1 Foundation Runtime Evidence

**Current status:** BLOCKED

Required live evidence:

- customer subnet controls and active route-table profile;
- Premium internal APIM and system identity;
- approved classic platform public IP;
- private DNS A records for gateway, developer, portal, management, and SCM;
- private resolution/reachability from an authorized internal network;
- TLS and weak-protocol settings;
- AllLogs/AllMetrics diagnostic destination, including policy-owned settings;
- average capacity alert threshold of at least 60 percent.

Run from the authorized environment:

```bash
APIM_VALIDATE_ENDPOINT_REACHABILITY=true \
  specs/02-apim-ai-gateway/validation/validate.sh foundation
```

No Foundry resource is required for this evidence.
