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
- **Capture output travels through `APIM_EXISTING_HOSTNAMES_JSON`.** The `.bicepparam` files read
  it with `readEnvironmentVariable`, defaulting to `[]`, so repository validators compile without a
  live service and no captured file is written or git-ignored.
- **`hostnameMode` over a boolean.** `preserve` re-sends captured domains; `merge` adds declared
  domains (declared wins on type + case-insensitive hostName, and on type for non-`Proxy` types);
  `replace` is declarative.
- **Secure certificate object.** `hostnameCertificates` is `@secure()` and keyed by
  `certificateKey`, because `@secure()` cannot decorate arrays. Values come from environment
  variables or a pipeline secret.
- **Script drops PFX-backed live entries.** APIM never returns the PFX, so they cannot be
  preserved; the script warns and the operator declares them with `merge` or `replace`.

## Risks / Trade-offs

- [Operator skips the script; the empty default removes domains in `preserve`/`merge`] →
  README marks the step required and `what-if` shows the removal. No in-template guard is
  possible; residual risk requires user acceptance.
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
