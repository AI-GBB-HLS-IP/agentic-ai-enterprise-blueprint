# Idempotency evidence (T038)

Status: **PARTIAL PASS (repeated pre-deployment what-if is stable)**

## Procedure

1. Run initial what-if (capture in `us1-what-if.md` or `us3-what-if.md`).
2. Re-run with unchanged parameters:

```bash
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam \
  --result-format ResourceIdOnly
```

3. Compare change set outputs.

## Pass criteria

- No duplicate DNS zones, links, role assignments, backends, APIs, products, or diagnostics.
- No unexpected mutation on network foundation or Chapter 01 Foundry resources.

## Observed comparison (2026-08-23)

- Repeated what-if runs returned the same summary:
  - `15 create`, `1 deploy` (`snet-apim` update), `38 ignore`, `1 potential` (`azure-api.net` A record).
- No duplicate resource declarations appeared between runs.
- Post-deployment idempotency must still be verified after first successful deployment create.
