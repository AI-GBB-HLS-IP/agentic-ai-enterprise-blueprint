## Why

Redeploying `infra/envs/poc/apim.bicep` (for example changing the SKU from Developer to Premium)
removed every APIM custom domain. The APIM service resource is deployed with a full PUT, and the
template declares no `hostnameConfigurations`, so ARM treats the property as an empty list.
Domains added outside Bicep are therefore deleted on every redeploy. Operators also hold PFX
certificates for the gateway, developer portal and management endpoints, which APIM never returns
and which therefore cannot be read back from the live service.

## What Changes

- Add `hostnameMode` (`preserve` default, `merge`, `replace`), `existingHostnameConfigurations`,
  `hostnameConfigurations` and a secure `hostnameCertificates` object to the APIM module and the
  `apim.bicep` environment template.
- Add `scripts/apim/get-existing-hostnames.sh`, which prints the live custom
  domains as JSON for the `APIM_EXISTING_HOSTNAMES_JSON` variable read by the `.bicepparam` files.
- Add `hostnameMode`/existing-domain parameters to `apim.bicepparam` and gateway, developer portal
  and management PFX examples (placeholder hostnames) to `apim.customer.example.bicepparam`.
- Fail `preserve`/`merge` deployments when the captured list is not supplied, and fail when more
  than one `Proxy` domain would set `defaultSslBinding`.
- Document in `infra/envs/poc/README.md` that the script must run before every deployment in
  `preserve` or `merge` mode.
- Add a mocked-CLI regression test for the capture script.
- Out of scope: creating certificates, Key Vault access, private DNS records for custom hostnames,
  and preserving PFX-backed domains automatically (they must be declared).

## Capabilities

### New Capabilities
- `apim-custom-domain-preservation`: APIM foundation redeployments keep, add to, or explicitly
  replace custom domains instead of silently removing them.

### Modified Capabilities

## Impact

- `infra/modules/apim/main.bicep`, `infra/envs/poc/apim.bicep`, `apim.bicepparam`,
  `apim.customer.example.bicepparam`, `infra/envs/poc/README.md`
- New `scripts/apim/get-existing-hostnames.sh`
- Deployment procedure: the script must run first; skipping it in `preserve`/`merge` mode fails the
  deployment.
