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

### Requirement: Reuse approved private monitoring connectivity
The POC SHALL reuse the supplied approved Log Analytics workspace and AMPLS for the connected
network/DNS domain. The required workspace and Application Insights associations, private
endpoints, DNS resolution, ingestion/query access settings, and permitted sender identities SHALL
be verified before observability is ready. Centrally managed resources SHALL be changed only
through their approved ownership process, without changing unrelated monitoring access.

An unavailable association or private route SHALL block that telemetry path; the POC SHALL NOT
create a competing AMPLS/workspace, weaken shared access settings, or silently use public ingestion.
AKS, Foundry, and APIM telemetry paths SHALL be assessed independently; success from one runtime
SHALL NOT be presented as proof for another.

#### Scenario: Reuse the shared monitoring path
- **WHEN** the approved workspace, AMPLS, resource associations, private endpoint, and DNS are available
- **THEN** a trace from each required sender arrives at its intended component through that sender's approved private path without replacing existing monitoring resources

#### Scenario: Missing approval or unsupported telemetry route
- **WHEN** AMPLS association authority, required DNS, an authorized sender, or a supported private route for a runtime is unavailable
- **THEN** the affected observability gate remains blocked and overall demonstration readiness does not pass

### Requirement: Correlated dependency telemetry
The solution SHALL correlate each end-to-end validation request across the agent, Foundry IQ,
APIM, tool backend, Cosmos DB, and relevant Azure dependencies.

#### Scenario: Investigate one transaction
- **WHEN** an operator selects a validation correlation identifier
- **THEN** the operator can reconstruct the ordered agent, retrieval, tool, memory, and dependency operations and their durations

### Requirement: Repeatable end-to-end validation
The solution SHALL provide an automated validation that exercises both agents against the same
approved grounding, tool, memory, identity, and connectivity scenarios. Initial acceptance SHALL
cover the Foundry prompt agent and AKS agent, not the deferred Foundry-managed hosted agent.

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
