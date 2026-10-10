## Context

`infra/modules/apim/main.bicep` deploys `Microsoft.ApiManagement/service@2024-05-01` with a full
PUT. Omitting `hostnameConfigurations` is treated as empty, and Bicep has no "leave property
untouched" construct (a conditional `null` is equivalent to omission). Hostname configurations are
a property of the service, not a child resource, so they cannot be split into a separate stage
without redeclaring the whole service. See proposal.md.

## Goals / Non-Goals

**Goals:** domains survive redeploys by default; operators can add or replace domains, including
PFX-backed gateway, developer portal and management domains, without committing secrets.

**Non-Goals:** certificate or Key Vault provisioning, private DNS for custom hostnames,
automatic preservation of PFX domains, an in-template read of the live service.

## Decisions

- **Read-then-resend via a capture script.** Alternatives rejected: an `existing` reference to the
  same service in the template (self-dependency and fails on first deploy); managing domains
  outside Bicep with `az apim update` (drift, not in the template).
- **Capture output travels through `APIM_EXISTING_HOSTNAMES_JSON` and fails closed.** The
  `.bicepparam` files read it into the string parameter `existingHostnamesJson` with an empty
  default. `apim.bicep` uses the existing `fail()` validation pattern to reject an empty value in
  `preserve`/`merge` mode, so repository validators still compile without a live service while a
  deployment without the capture step cannot remove domains. An explicit `[]` is accepted.
- **One default binding.** In `merge`, retained `Proxy` entries lose `defaultSslBinding` when a
  declared `Proxy` claims it, and the module fails if more than one `Proxy` would set it.
- **`hostnameMode` over a boolean.** `preserve` re-sends captured domains; `merge` adds declared
  domains (declared wins on type + case-insensitive hostName, and on type for non-`Proxy` types);
  `replace` is declarative.
- **Secure certificate object.** `hostnameCertificates` is `@secure()` and keyed by
  `certificateKey`, because `@secure()` cannot decorate arrays. Values come from environment
  variables or a pipeline secret.
- **Script drops PFX-backed live entries.** APIM never returns the PFX, so they cannot be
  preserved; the script warns and the operator declares them with `merge` or `replace`.

## Risks / Trade-offs

- [Operator skips the script] → the deployment fails in `preserve`/`merge` mode (fail-closed).
  Residual: running the script against the wrong service, or supplying `[]` by hand, still
  removes domains; `what-if` review is the mitigation.
- [Captured entry rejected by the API, or a captured and a declared entry both set
  `defaultSslBinding`] → script passes the full live object except read-only certificate fields; verify with what-if or a deploy on
  a non-production service.
- [Merge expression evaluated only by `bicep snapshot`, which does not expand lambdas] → live
  validation task is BLOCKED until a non-production APIM is available.
- [Custom hostnames unreachable in the internal VNet without DNS records] → documented; DNS is a
  separate change.

## Migration Plan

Existing deployments: run the script, then deploy as documented; declare any PFX domains and use
`merge` or `replace`. Rollback: redeploy the previous template revision; removed domains must be
re-added.
