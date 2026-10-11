# Proposal

## Why

The APIM foundation currently requires five built-in `azure-api.net` endpoints to resolve
directly to APIM's private VIP. Organizations can block those names and use custom domains
through approved corporate private-access infrastructure instead. Azure also documents that
custom non-gateway bindings can replace the corresponding default endpoint, making the current
unconditional built-in checks unsuitable for those configurations.

## What Changes

- Add explicit endpoint selection (`built-in`, default; `custom`) as a separate input from DNS
  ownership and certificate handling. Built-in mode supports `blueprint` or `external` DNS;
  custom mode requires `external` DNS and rejects `custom`/`blueprint`. Certificate handling
  (`preserve`, `merge`, `replace`) remains unchanged.
- Custom mode requires configured gateway, developer portal, and management hostnames and
  excludes built-in legacy portal and SCM from the client-access gate.
- Keep built-in/direct-private validation compatible. Custom mode supports direct-private
  access or evidence-backed corporate routing, without accepting arbitrary addresses or a
  successful HTTP response as proof of APIM identity.
- Emit a selected-endpoint handoff and record validation evidence bound to the selected APIM,
  endpoints, and access path. Require explicit `status: pass` for custom readiness; failed,
  blocked, or missing outcomes cannot advance readiness. Preserve Stage 2's readiness prerequisite.
- Use the selected gateway for integration requests and dependent consumers; allow explicit
  overrides only when consistent with the selected live binding and HTTPS port 443.
- Update chapter specification, contracts, operator instructions, examples, and regressions.
- No certificate lifecycle change, corporate DNS/proxy provisioning, platform dependency
  firewall changes, or claim that client access proves APIM-to-Foundry connectivity.

## Capabilities

### New Capabilities

- `apim-endpoint-access`: Mode-aware APIM client endpoint selection, routing validation,
  readiness handoff, and integration URL selection.

### Modified Capabilities

None registered under `openspec/specs/` (`openspec list --specs` returned no specs).
Implementation must reconcile the root Chapter 02 specification and the active
`split-apim-foundry-deployment` and `preserve-apim-custom-domains` contracts.

## Impact

- Tracking: #104; branch `spec/apim-custom-endpoint-access`.
- Foundation: `infra/envs/poc/apim.bicep`, both foundation parameter examples,
  `infra/modules/apim/private-dns.bicep`, and selected gateway outputs.
- Integration: `infra/envs/poc/apim-foundry-integration.bicep`, parameter examples,
  `specs/02-apim-ai-gateway/validation/validate.sh`, request examples, and gateway consumers.
- Documentation/tests: Chapter 02 spec, plan/tasks/contracts and validation guidance,
  `infra/envs/poc/README.md`, staged/hostname regression tests.
- Approved scope: three mandatory custom endpoints; legacy portal/SCM excluded only from
  custom client acceptance; corporate routing requires network-owner evidence.
- Feasibility: Microsoft Learn internal-VNet and custom-domain documentation, and inspected
  live-binding helpers, DNS handoff, runtime validator, and existing-resource Stage 2 template.
  Corporate route identity remains an operator-attested fact, not an ARM-enforced guarantee.
  Live evidence is mandatory for deployment approval, not for publishing this specification.
