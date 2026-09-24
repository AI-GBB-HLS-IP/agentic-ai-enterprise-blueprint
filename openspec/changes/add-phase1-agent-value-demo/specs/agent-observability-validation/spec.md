## Purpose

Defines the telemetry, correlation, validation, and evidence required to prove the Phase 1
end-to-end agent value demonstration.

## ADDED Requirements

### Requirement: Separate APIM and agent telemetry components
The solution SHALL retain the APIM-dedicated Application Insights component and SHALL use a
separate Application Insights component for prompt-agent, AKS-agent, and validation telemetry.

#### Scenario: Route gateway telemetry
- **WHEN** APIM processes a tool request
- **THEN** gateway request and policy telemetry remains available through the APIM observability component

#### Scenario: Route agent telemetry
- **WHEN** either agent handles a validation request
- **THEN** its request, trace, exception, and dependency telemetry is available through the agent observability component

### Requirement: Correlated dependency telemetry
The solution SHALL correlate each end-to-end validation request across the agent, Foundry IQ,
APIM, tool backend, Cosmos DB, and relevant Azure dependencies.

#### Scenario: Investigate one transaction
- **WHEN** an operator selects a validation correlation identifier
- **THEN** the operator can reconstruct the ordered agent, retrieval, tool, memory, and dependency operations and their durations

### Requirement: Repeatable end-to-end validation
The solution SHALL provide an automated validation that exercises both agents against the same
approved grounding, tool, memory, identity, and connectivity scenarios.

#### Scenario: Pass the value demonstration
- **WHEN** both agents return expected grounded answers with citations, complete the approved APIM tool call, persist and resume conversation state, and emit correlated telemetry
- **THEN** the validation reports Phase 1 functional readiness as passed

#### Scenario: Fail closed on incomplete evidence
- **WHEN** either agent fails grounding, citation, tool, memory, AKS readiness, private connectivity, identity, or telemetry checks
- **THEN** the validation identifies the failed gate and does not report complete Phase 1 readiness

### Requirement: Safe validation evidence
Validation artifacts SHALL exclude credentials, access tokens, confidential content, customer
identifiers, and unnecessary message or document bodies.

#### Scenario: Publish validation evidence
- **WHEN** evidence is written to a file, workflow log, issue, or pull request
- **THEN** it contains only generic identifiers, redacted operational metadata, status, timing, and the minimum result details needed for review
