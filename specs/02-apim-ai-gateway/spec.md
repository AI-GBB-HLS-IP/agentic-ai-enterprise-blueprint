# Feature Specification: Staged APIM AI Gateway

**Status:** Implementation in progress
**Tracking issue:** #71
**Branch:** `feat/split-apim-foundry-deployment`

## Goal

Deploy Chapter 02 through two independently deployable and independently verifiable stages.
Stage 1 provides a usable private APIM foundation without Foundry. Stage 2 adds a governed
Foundry-backed API after the separate customer Foundry governance process is complete.

### Related Phase 1 agent value demonstration

[Issue #83](https://github.com/AI-GBB-HLS-IP/agentic-ai-enterprise-blueprint/issues/83) and the
[OpenSpec change](../../openspec/changes/add-phase1-agent-value-demo/proposal.md) scope a
separate read-only tool API for the Foundry prompt agent and independent AKS agent. The tool API
uses approved Entra caller identities without subscription keys; APIM's existing model API
authentication remains unchanged. Initial acceptance uses one Foundry account with repeatable
project onboarding and a second-project non-interference check. The Foundry-managed Hosted Agent
is a later follow-on, while business-unit accounts and permanent production
isolation/capacity/chargeback/retention topology remain deferred. This link does not claim those
tool integrations or runtime paths are already deployed.

## Stage 1 — APIM Foundation

### Inputs

- Existing VNet, APIM subnet, approved NSG, and route table or documented tenant exception.
- Evidence for an `apimsubnet-*` name or a documented naming exception.
- Four required service endpoints and no subnet delegation.
- APIM name, approved Developer or Premium capacity, corporate publisher identity, and approved
  public IP name, DNS label, and tags.
- Private DNS ownership mode, zone/record names, or external corporate-DNS handoff.
- Endpoint selection and access path as defined below, independent of certificate handling.
- Application Insights, Log Analytics, diagnostics ownership, and capacity-alert settings.
- Public-network policy handoff (`Enabled` during activation unless an approved private endpoint
  permits `Disabled`).

### Owned Resources

- `Microsoft.ApiManagement/service` with system-assigned identity and internal VNet injection.
- `azure-api.net` private DNS zone, VNet link, and internal endpoint A records when
  blueprint-owned; otherwise an external DNS handoff containing hostnames and private IPs.
- Application Insights, APIM logger/diagnostic, and optional Log Analytics workspace.
- APIM resource diagnostic settings when blueprint-owned.
- Average APIM capacity alert with a threshold of 60 percent.

The foundation creates the approved Standard static public IP used for classic internal APIM
platform management. Its presence is not evidence that gateway, portal, management, or SCM
endpoints are public.

### Foundation Requirements

- Foundation deployment and validation MUST perform no Foundry account, model, role, backend, or
  governed API lookup.
- APIM MUST use Developer for smoke testing or Premium for production-like validation, internal
  VNet mode, a system-assigned identity, HTTPS backends, TLS 1.2 or stronger, and disabled legacy
  protocols/ciphers. Developer capacity MUST be `1`.
- Subnet validation MUST fail before deployment for an unapproved name, missing approved NSG,
  missing route table without exception evidence, any delegation, or missing required service
  endpoint.
- Diagnostics MUST collect `AllLogs` and `AllMetrics` through the customer-required destination.
  When Azure Policy owns diagnostics, validation MUST inspect the policy-created setting and the
  template MUST NOT deploy a conflicting setting.
- Foundation readiness MUST be independent of integration status.

### Foundation Outputs

`apimServiceId`, `apimServiceName`, `apimGatewayHostname`, `apimPrincipalId`,
`privateIpAddresses`, DNS and observability resource IDs, `foundationReadiness`, and
`integrationReadiness: not-deployed`.

### Endpoint Access Contract

Implementation and acceptance are tracked by #104 in
`openspec/changes/support-apim-custom-endpoint-access/tasks.md`. Its
`specs/apim-endpoint-access/spec.md` and design D1-D5 define the requirements, scenarios,
and cross-surface ownership.

| Endpoint mode | DNS ownership | Access path | Client acceptance |
|---|---|---|---|
| `built-in` (default) | `blueprint` or `external` | `direct-private` (default) | Existing five built-in endpoints, DNS to live private VIP, validated TLS |
| `custom` | `external` only | `direct-private` | Gateway, developer portal, management; role-matched bindings, DNS to live private VIP, validated TLS |
| `custom` | `external` only | `corporate-routed` | Same three bindings, DNS/TLS, and retained network-owner routing approval |

All other combinations MUST fail explicitly. Custom names MUST be normalized lowercase DNS
names, not URLs, ports, paths, wildcards, or missing roles. Custom mode MUST NOT probe built-in
names; legacy portal/SCM are excluded only from custom client acceptance, not removed as
platform features. Platform network dependencies remain unchanged.

Foundation MUST validate custom selections against the effective certificate binding assembly
and runtime MUST verify the corresponding live Proxy, DeveloperPortal, and Management bindings
on the intended classic Internal APIM. `hostnameMode` remains `preserve`/`merge`/`replace`;
capture and manual PFX resupply remain mandatory where applicable.

Additive `endpointAccess`, `selectedGatewayHostname`, selected gateway URL, and mode-aware
`privateDnsHandoff` MUST identify the service, selected roles, path, exclusions, and evidence.
`apimGatewayHostname` retains its built-in compatibility value.

Custom readiness requires matching `endpointValidationEvidence` with every exact generic
base field (`validationType`, `status`, `owner`, `scope`, `approvalReference`,
`evidenceSummary`, `timestampUtc`) and extension field (`apimServiceId`, `endpointMode`,
`endpointAccessPath`, `selectedHostnames`, `validationReference`), plus
`routingApprovalReference` and `owner: network-owner` for corporate routing.
Fields are non-empty strings except the exact three-role hostname map. The gate name is
`apim-endpoint-access`; runtime requires ISO-8601 UTC `timestampUtc`, with no timestamp aliases.
Only complete, valid, context-matching `status: pass` evidence can advance custom DNS
readiness. Missing evidence remains pending/BLOCKED; fail/blocked evidence cannot advance;
invalid or mismatched records are rejected.

Generic base fields remain redacted under
`../00-network-foundation/contracts/validation-evidence.md`; live extension context belongs
only in untracked inputs/handoffs and the approved customer evidence store. Corporate approval
attests to the intended Internal upstream and client route without unapproved public exposure;
DNS, TLS, HTTP responses, or an IP range alone cannot prove that route's APIM origin.
Revalidate after service, route, hostname, or certificate changes.

Stage 2 MUST verify selected metadata and passing custom evidence even if overall readiness
claims deployed, and match the live gateway binding. Legacy handoffs are accepted only for
built-in/direct-private. Integration requests and D5's inventoried instructional consumers
MUST use selected gateway URLs while preserving API paths and independent Foundry/API Center
endpoints. Overrides MUST match HTTPS, selected host, configured path, no userinfo, and implicit
or explicit port 443 before credentials are used. Stage 2 remains existing-resource-only and
requires separate Foundry/model/identity/request/telemetry acceptance.

Workspace gateways, v2 management, multi-region mapping, wildcard selection, corporate
network provisioning, and Chapter 14's separate topology are excluded. Local evaluation does
not satisfy live task 4.2 or deployment approval.

## Stage 2 — Foundry Integration

### Inputs

- Existing APIM service name and resource group.
- Existing Foundry account name, resource group, and resource ID.
- GenAI Review Board approval and Foundry account-enablement evidence references.
- Maintained customer policy source for allowed regions and approved models.
- Foundry private-access requirement.
- Approved public-model to deployment mappings.
- Backend, API, product, token-limit, and API-version settings.

### Owned Resources

- `Cognitive Services OpenAI User` assignment scoped only to the selected Foundry account.
- APIM Foundry backend using HTTPS and system-assigned managed identity.
- Approved-model named value.
- Governed chat API, operation, product binding, and policies.

Stage 2 references APIM as existing and MUST NOT deploy or modify the APIM service, VNet
injection, private DNS, Application Insights, Log Analytics, APIM resource diagnostics, or
capacity alert.

### Integration Requirements

- Integration preflight MUST fail if governance evidence is absent, the Foundry account is outside
  the approved region policy, public network access is enabled, no approved model mapping is
  supplied, or a mapped deployment does not exist.
- The APIM principal ID MUST be derived from the existing APIM resource.
- Unsupported model aliases and unauthenticated requests MUST fail before Foundry forwarding.
- No Foundry key, connection string, prompt, completion, or subscription credential may be logged
  or stored by the integration templates.
- Integration failure MUST NOT change foundation readiness.

### Integration Outputs

Role assignment, backend, API, product, approved-model named value and count, model mappings, and
`integrationReadiness`.

## Validation Modes

- `validate.sh foundation` compiles and checks only Stage 1 and performs no Cognitive Services
  lookup.
- `validate.sh integration` verifies the existing APIM identity, Foundry governance and runtime
  prerequisites, then compiles/checks Stage 2.
- `validate.sh all` runs foundation and integration in that order.

Offline structural checks are distinct from Azure what-if and runtime evidence. A missing Azure
session, inaccessible resource, or absent approval reference is `BLOCKED`, never a successful
fallback.

## Acceptance Criteria

1. Foundation compiles, previews, and can deploy with no Foundry parameter or permission.
2. Foundation validation proves customer network, security, private endpoint, DNS, diagnostics,
   and capacity-monitoring controls.
3. Integration compiles and references the existing APIM identity.
4. Integration preview contains only integration-owned resources.
5. Readiness and evidence are reported separately for both stages.
6. Reapplying either stage with unchanged inputs proposes no duplicate or unexpected changes.
7. Stage 2 request and telemetry checks prove allowed requests succeed and rejected requests do
   not reach Foundry, without logging secrets or payloads.

## Rollback

Stage 2 rollback removes only integration-owned role/API/backend/model resources. Stage 1
rollback follows the APIM foundation procedure and does not modify Foundry.
