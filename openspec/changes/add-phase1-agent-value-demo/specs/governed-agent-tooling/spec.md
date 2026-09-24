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
Tool calls SHALL use an approved identity flow and SHALL be subject to APIM authentication,
authorization, throttling, logging, and other configured governance policies.

#### Scenario: Authorized agent call
- **WHEN** an approved agent identity calls the APIM tool endpoint
- **THEN** APIM validates the caller and applies the configured policies before invoking the backend

#### Scenario: Unauthorized agent call
- **WHEN** a caller lacks the required identity, claim, role, or subscription policy
- **THEN** APIM rejects the call without forwarding it to the backend

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
