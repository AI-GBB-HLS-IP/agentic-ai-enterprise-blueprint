## Purpose

Defines the governed tool-access boundary through APIM for both Phase 1 agent implementations.

## ADDED Requirements

### Requirement: Approved tool invocation through APIM
Both agents SHALL invoke approved external tools through APIM and SHALL NOT call the protected
tool backend directly.

#### Scenario: Invoke an approved tool
- **WHEN** an agent determines that an approved tool is required
- **THEN** the request is sent to the APIM endpoint and APIM forwards the authorized request to the configured backend

#### Scenario: Prevent gateway bypass
- **WHEN** an agent is configured for a protected tool
- **THEN** its runtime configuration exposes the APIM endpoint rather than the backend service endpoint

### Requirement: Managed authentication and policy enforcement
The new POC tool API SHALL authenticate Entra application tokens for the approved tenant and API
audience and authorize explicitly approved caller principals. The AKS caller SHALL use workload
identity; the Foundry caller SHALL use the managed identity supported and verified for the chosen
tool integration. The API SHALL NOT require subscription keys or client secrets. Existing model
API authentication SHALL remain unchanged.

APIM SHALL enforce caller authorization, throttling, logging, and timeout/error policies before
invoking the backend. The backend SHALL authorize APIM's managed identity, not the original
agent token. Agents SHALL have neither backend invocation permission nor a direct backend fallback.
The POC SHALL NOT claim per-agent authorization for agents sharing the same Foundry caller
principal, or treat caller-supplied agent/project identifiers as authorization evidence.

#### Scenario: Authorized agent call
- **WHEN** an approved caller principal presents a valid Entra token for the tool API
- **THEN** APIM validates the caller and applies the configured policies before invoking the backend

#### Scenario: Unauthorized agent call
- **WHEN** a caller supplies no token, an expired token, a token for another tenant or audience, or a valid token from an unapproved principal
- **THEN** APIM rejects the call without forwarding it to the backend

#### Scenario: Backend trusts only the gateway identity
- **WHEN** the backend receives a request
- **THEN** it accepts only the authorized APIM principal with a valid backend-audience token and rejects direct agent credentials, even if an agent correlation header is present

#### Scenario: Verify the Foundry caller
- **WHEN** the configured Foundry tool's actual caller principal and supported token audience have not been verified for the selected runtime/API version
- **THEN** Foundry tool activation remains blocked rather than authorizing both account and project identities speculatively or falling back to a key

#### Scenario: Shared identity is not individual-agent authorization
- **WHEN** two Foundry agents use the same verified caller principal
- **THEN** APIM applies the same POC tool permission to that principal and does not grant additional permissions based on an agent or project header

### Requirement: One deterministic read-only tool
The initial POC SHALL expose one approved read-only lookup operation over generic fixture data
through an OpenAPI-described APIM endpoint. It SHALL have a stable request/response contract and
controlled not-found and backend-failure behavior, without executing customer-side actions.

#### Scenario: Reproduce the tool result
- **WHEN** either agent submits the same known fixture identifier
- **THEN** it receives the declared stable result through APIM, while an unknown identifier produces an explicit not-found result rather than a fabricated success

### Requirement: Explicit tool failure behavior
Tool authentication, policy, timeout, and backend failures SHALL be returned as distinguishable
agent-visible failures and recorded in telemetry.

#### Scenario: Backend operation fails
- **WHEN** APIM receives an error or timeout from the tool backend
- **THEN** the agent receives a failure result that does not claim the requested action succeeded

### Requirement: End-to-end correlation
Each tool invocation SHALL preserve or propagate a correlation identifier across the agent,
APIM, and tool backend boundaries.

#### Scenario: Trace a tool call
- **WHEN** a validation request causes an agent to invoke a tool
- **THEN** an operator can correlate the agent operation with the APIM request and backend dependency using the recorded identifier
