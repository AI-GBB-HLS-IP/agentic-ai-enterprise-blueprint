# Design

## Context

See `proposal.md` for motivation. Current `private-dns.bicep` always emits five built-in
names; `apim.bicep` fixes its zone/record contract to `azure-api.net`; runtime
`validate_apim_endpoint_reachability` in the Chapter 02 validator requires private-IP
equality for all five. `apim-foundry-integration.bicep` checks readiness but does not
know endpoint selection. Its request validator defaults to the built-in gateway.

Feasibility sources:

- [Internal VNet](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet):
  endpoints require operator DNS; Internal mode and network dependencies remain.
- [Custom domains](https://learn.microsoft.com/en-us/azure/api-management/configure-custom-domain):
  configured Host headers and matching certificates are supported; custom non-gateway
  domains replace defaults, while the default gateway remains configured.
- `infra/modules/apim/hostnames.bicep`: existing certificate expansion/merge must remain intact.
- `infra/envs/poc/apim-foundry-integration.bicep`: existing-resource semantics keep Stage 2
  separate from foundation mutation; this change does not alter role scopes or deployment order.

## Goals / Non-Goals

**Goals:** deterministic endpoint selection; no built-in client lookup in custom mode;
explicit distinction between direct-private measurement and operator-attested routing.

**Non-Goals:** provision intermediary networks or corporate DNS; relax backend security;
detect arbitrary proxy topology automatically; guarantee no platform dependency uses an
Azure-managed name; change certificate handling or allow overlapping foundation deployments.

## Decisions

### D1: Endpoint mode is separate from ownership

Add `endpointMode` (`built-in` default, `custom`), `endpointAccessPath`
(`direct-private` default, `corporate-routed`), and `customEndpointHostnames`
object with `gateway`, `developerPortal`, `management`. Parameter examples expose
`APIM_ENDPOINT_MODE`, `APIM_ENDPOINT_ACCESS_PATH`, `APIM_CUSTOM_ENDPOINT_HOSTNAMES`.
Normalize lowercase DNS names; reject schemes, ports, paths, wildcard selections, and
missing entries. Corporate-routed is valid only with custom/external. Custom mode uses
external DNS ownership; custom/blueprint fails explicitly rather than creating corporate
zones. Built-in/blueprint and built-in/external stay supported.

This limited matrix avoids inventing workload ownership of corporate DNS. Keep the
existing built-in zone contract for its resource branch, not as a universal endpoint rule.
Do not use hostnameMode to choose endpoints: it controls certificate request assembly.

### D2: Typed endpoints and preserved certificate semantics

Derive a selected endpoint list with roles and a selected gateway URL. Emit additive
`endpointAccess` metadata and mode-aware `privateDnsHandoff`; keep
`apimGatewayHostname` as its existing built-in value for compatibility and add
`selectedGatewayHostname`. Custom handoff lists only the three mandatory endpoints and
names legacy portal/SCM as excluded client checks. It does not delete those platform
features or change Azure infrastructure networking.

Validate selected custom names against effective hostname bindings during foundation
deployment and against live bindings at runtime, including case-insensitive matching
and matching endpoint type. Reuse hostname resolution helpers; do not reimplement PFX
capture. Manual/PFX-managed domains still require resupply on foundation redeploy.

### D3: Two verification paths, no broad IP exception

Direct-private retains current DNS-to-live-VIP equality and certificate-validated HTTPS.
Corporate-routed performs live binding, Internal SKU/posture, DNS, and TLS checks, plus
requires `endpointValidationEvidence` context and network-owner attestation. Root HTTP
responses measure transport, not APIM origin or application success. Evidence records:
service ID, mode, access path, exact role/hostname map, validation timestamp, non-placeholder
validation reference, and corporate-only routing approval reference. The referenced
network-owner record must identify the intended Internal APIM upstream and approved
client path without unapproved public exposure. Retain it in the customer evidence store.

Expose `APIM_ENDPOINT_VALIDATION_EVIDENCE` JSON in parameter files. Structural/equality
checks can enforce context; they cannot authenticate the external record, verify its
author, or detect every route change. Operator approval is explicitly required and
revalidation is required after routing/hostname/certificate/service changes. Do not
present non-empty strings, timestamps, TLS interception trust, or 100.64/10 as proof.
Preserve the standard external-DNS evidence reference for legacy built-in configurations.

### D4: Readiness and integration consistency

Keep DNS readiness pending until appropriate evidence is supplied; retain all other
foundation gates. Bicep records operator evidence, while runtime validation establishes
measured checks; an ARM success is not live proof. Stage 2 takes selected endpoint
metadata from the handoff, checks its service/selection consistency and the selected
live gateway binding, and does not create APIM/DNS/monitoring.

For a legacy handoff without endpoint metadata, accept only built-in/direct-private
selection; reject any custom input without a custom handoff. Default request URLs use
selected gateway and API path. Validate any `APIM_INTEGRATION_REQUEST_URL` override
before using secrets, including HTTPS scheme, host, port, configured path, and absence
of userinfo. Explicit client settings in future agent work consume the selected URL;
never silently rewrite a Foundry backend endpoint to the APIM hostname.

### D5: Coverage and traceability

All spec references below are relative to this change; each requirement and all of its
scenarios are covered by the named tasks.

| Requirement in `specs/apim-endpoint-access/spec.md` | Decisions | Affected surfaces/modes | Tasks | Acceptance scenarios |
|---|---|---|---|---|
| Explicit endpoint modes | D1, D2 | Foundation Bicep, both parameter files, runtime endpoint selection; built-in/blueprint, built-in/external, custom/external; custom/blueprint rejected | 1.1, 2.1, 2.2, 4.1 | Existing standard configuration; Built-in names are blocked; Incomplete custom configuration; Unsupported custom DNS ownership |
| Live endpoint binding verification | D2, D3 | Effective/live bindings, foundation/all runtime validator | 2.1, 2.2, 4.1 | Valid custom bindings; Wrong service or invalid certificate |
| Access-path-specific verification | D1, D3 | Direct and corporate branches, evidence validation | 2.2, 4.1, 4.2 | Direct custom access; Approved intermediary; Unproven intermediary |
| Context-bound readiness handoff | D2, D3, D4 | DNS module, foundation outputs, runtime evidence validation, Stage 2 preflight/Bicep | 2.1, 2.2, 3.1, 4.1 | Custom readiness completed; Changed selection or stale evidence; Legacy standard handoff |
| Selected gateway integration | D2, D4 | Foundation endpoint selection, integration/all requests, URL output/overrides, client examples | 2.1, 2.2, 3.1, 3.2, 4.1, 4.2 | Custom gateway request; Conflicting override |
| Explicit operational limits | D3, D5 | Chapter 02 spec/plan/tasks/contracts, README, runtime evidence guidance, validation docs, related active artifacts | 1.1, 2.2, 3.2, 4.2 | Custom-only organization |

Affected callers include `foundation`, `integration`, `all`, offline compile/static checks,
runtime checks, foundation handoff consumers, default and overridden integration requests,
and selected gateway output consumers. DNS ownership and endpoint selection are orthogonal
within the allowed matrix. Diagnostics policy/blueprint ownership, Developer/Premium SKU,
Foundry resource scopes, certificate preserve/merge/replace, and cross-stage ownership
remain unchanged. Workspace gateways, v2-tier management, multi-region endpoint mapping,
custom wildcard selection, and provisioning corporate routing are excluded.

## Risks / Trade-offs

- Corporate origin cannot be proven from curl alone -> named network-owner approval plus
  live bindings/transport evidence; mark absent evidence BLOCKED.
- Built-in compatibility retains assumptions unsuitable after custom non-gateway bindings ->
  operator must select custom mode; do not silently infer the mode or weaken standard checks.
- Stage 1 updates can alter custom certificate bindings -> keep existing PFX handling and
  inspect what-if; no parallel foundation updates.
- Evidence can become stale without a name change -> mandatory operator revalidation on
  route/certificate changes; no claim of continuous monitoring.
- Client-access success does not prove private Foundry access -> retain separate model,
  managed-identity, backend routing, request, and telemetry acceptance.

## Migration Plan

Keep old default inputs/outputs working. Add parameters and selected endpoint metadata,
update validator and documentation together, and reconcile related active artifacts in
task 1.1. Custom operators select external/custom plus their approved access path, keep
certificates intact, run checks, record evidence, preview/redeploy foundation, and regenerate
the handoff from that exact deployment before Stage 2. A mode or upstream change invalidates
the evidence. Rollback to built-in requires restoring actual built-in access; it is not
valid where policy blocks those names.

## Readiness Record

User approved three mandatory custom endpoints, legacy portal/SCM client exclusions,
and evidence-backed corporate routing. Proposal changes no live resources. Authoritative
platform feasibility is established for classic APIM custom bindings; external origin
attestation is explicitly not a platform guarantee. Implementation tests and live customer
route/backend evidence remain pending under tasks 4.1/4.2 and gate deployment acceptance,
not this proposal. No customer identifiers or secrets belong in committed artifacts.
