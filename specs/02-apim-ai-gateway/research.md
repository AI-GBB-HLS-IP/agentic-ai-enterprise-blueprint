# Research: APIM AI Gateway (Core Gateway)

## R1: Classic Premium VNet injection

**Decision**: Use `Microsoft.ApiManagement/service` with SKU `Premium`,
`virtualNetworkType: Internal`, and `virtualNetworkConfiguration.subnetResourceId` pointing at
the existing dedicated `snet-apim` subnet. Premium v2 remains the preferred future tier, but
classic Premium is the approved non-production architecture because it preserves the production
VNet-injected design while Premium v2 capacity is unavailable.

**Rationale**: Classic Premium VNet injection uses the dedicated APIM subnet directly and does not use the
stv2-specific `Microsoft.Web/serverFarms` delegation. The subnet must be validated as dedicated,
with its existing NSG association preserved, before APIM creation. VNet injection is configured
at APIM creation time and is not interchangeable with v2 outbound integration.

**Alternatives considered**:
- *`Microsoft.Web/serverFarms` delegation* — rejected for classic Premium; it is an stv2-specific
  requirement and is not part of this classic-tier design.
- *External VNet mode* — rejected; exposes a public gateway endpoint, which violates the
  private-by-default constitution principle.
- *Premium v2* — retained as the preferred future target, but not deployable in the current
  subscription/region due to the documented capacity restriction.

## R2: Private DNS zone naming

**Decision**: Create a new private DNS zone named `azure-api.net`, distinct from the existing
`privatelink.azure-api.net` zone already linked to `vnet-agent-factory-poc` by Network
Foundation.

**Rationale**: Internal-mode VNet-injected APIM instances publish their gateway hostname under
the `azure-api.net` zone (not a `privatelink.*` name), because clients inside the VNet resolve
the APIM instance's own custom/default hostname directly rather than through Azure Private Link's
standard `privatelink.<service>` convention. Reusing or renaming the existing
`privatelink.azure-api.net` zone would conflate two different Azure networking mechanisms
(Private Link private endpoints vs. VNet-injected internal-mode services) and is explicitly
called out as an edge case to avoid in `spec.md`.

**Alternatives considered**:
- *Reuse `privatelink.azure-api.net`* — rejected; wrong mechanism, would not resolve the internal
  VNet-injected hostname correctly and risks zone/record conflicts.

## R3: Backend authentication to Foundry

**Decision**: Configure the APIM backend for Foundry using the `authentication-managed-identity`
policy element with `resource="https://cognitiveservices.azure.com"`, relying on APIM's
system-assigned managed identity and its `Cognitive Services OpenAI User` role assignment scoped
to the `foundry-agent-factory-poc` account.

**Rationale**: This is the only backend-auth mechanism that avoids issuing, storing, or
transmitting a Foundry API key anywhere, consistent with Chapter 01's own no-key design and the
constitution's "private by default, no bypass" principle.

**Alternatives considered**:
- *API key in a named value/Key Vault reference* — rejected; reintroduces a long-lived secret
  this platform is explicitly designed to eliminate.
- *User-assigned managed identity* — rejected as unnecessary complexity for a single-gateway,
  single-backend POC; system-assigned identity is simpler to reason about and to audit for this
  scope, and does not preclude switching later if multiple APIM instances need to share an
  identity.

## R4: Observability

**Decision**: Reuse a Log Analytics workspace if Chapter 01 already created one in
`rg-agent-factory-poc`; otherwise create a new workspace. Add a dedicated Application Insights
component, an APIM logger resource pointing at it, and a diagnostic setting that captures gateway
and request logs while excluding request/response bodies and headers that could contain secrets.

**Rationale**: Confirming reuse-vs-create avoids duplicate Log Analytics workspaces in a small
POC resource group; excluding bodies/headers from logs avoids incidentally capturing subscription
keys or model payloads in a diagnostic sink.

**Alternatives considered**:
- *No observability in this increment* — rejected; FR-009 in `spec.md` requires it, and token
  metrics (FR-008) depend on the APIM logger/Application Insights pipeline to be emitted
  correctly.

## R5: Token rate limiting and metrics policy shape

**Decision**: Apply `llm-token-limit` and `llm-emit-token-metric` in the inbound policy pipeline
(keyed/dimensioned by `context.Subscription.Id` and API) on the client-facing
`chat/completions` API.

**Rationale**: APIM accepts `llm-emit-token-metric` only in the inbound section for this service.
The policy still derives token usage from the LLM response and satisfies FR-008's requirement for
subscription-attributable token consumption without requiring a custom logging pipeline.

**Alternatives considered**:
- *`azure-openai-token-limit` (legacy policy name)* — rejected in favor of the newer
  `llm-token-limit`/`llm-emit-token-metric` policies, which generalize across OpenAI-compatible
  backends and are what the blueprint chapter documents.

## Outstanding implementation-time confirmations

The following must be reconfirmed against the live subscription's provider API during
implementation, not assumed from this research alone (consistent with the Chapter 01 pattern of
treating provider behavior as a research gate, not a hard-coded guess):

1. The exact `Microsoft.ApiManagement/service` API version available in the target subscription
   that supports `virtualNetworkType: Internal` with stv2/stv2-compatible SKUs.
2. Whether a Log Analytics workspace already exists in `rg-agent-factory-poc` from Chapter 01 (to
   decide reuse vs. create).
3. The exact current schema/attribute names for `llm-token-limit` and `llm-emit-token-metric` in
   the APIM policy XML schema version available in this subscription.
4. Confirmation that `snet-apim` remains unused and unclaimed by any other resource before the
   delegation is applied.
