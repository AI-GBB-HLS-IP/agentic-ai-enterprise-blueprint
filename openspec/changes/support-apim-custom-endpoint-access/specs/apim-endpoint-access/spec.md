# Spec Delta

## Purpose

Support standard and custom APIM client endpoints without weakening internal-service,
certificate-validation, or evidence requirements for integration readiness.

## ADDED Requirements

### Requirement: Explicit endpoint modes
The foundation SHALL support `built-in` (default) with blueprint or external DNS and
`custom` with external DNS only; custom/blueprint SHALL fail explicitly. Custom mode
SHALL require gateway, developer portal, and management hostnames and SHALL exclude
built-in legacy portal and SCM from its client-access gate. Certificate handling and
platform network dependencies SHALL remain unchanged.

#### Scenario: Existing standard configuration
- **WHEN** endpoint mode is omitted
- **THEN** the existing five built-in endpoint checks and direct-private requirements remain.

#### Scenario: Built-in names are blocked
- **WHEN** custom mode is selected with all three required configured hostnames
- **THEN** client validation uses those names without resolving or probing built-in names.

#### Scenario: Incomplete custom configuration
- **WHEN** a required custom hostname is missing or is a URL, wildcard, or invalid hostname
- **THEN** configuration fails explicitly rather than falling back to built-in names.

#### Scenario: Unsupported custom DNS ownership
- **WHEN** custom endpoint mode is combined with blueprint DNS ownership
- **THEN** configuration fails explicitly without creating corporate DNS resources or
  falling back to built-in endpoints.

### Requirement: Live endpoint binding verification
Runtime validation SHALL match each selected custom hostname to its endpoint type on the
intended live APIM service, require supported classic SKU and Internal mode, and validate
DNS resolution and HTTPS certificates. Missing access SHALL be BLOCKED; mismatch or
failed checks SHALL fail. HTTP status alone SHALL NOT prove service identity.

#### Scenario: Valid custom bindings
- **WHEN** the three names match live Proxy, DeveloperPortal, and Management bindings and TLS succeeds
- **THEN** endpoint binding and transport checks pass independently of routing evidence.

#### Scenario: Wrong service or invalid certificate
- **WHEN** a selected hostname is not bound to the intended service or TLS validation fails
- **THEN** validation fails without certificate bypass or a success-shaped fallback.

### Requirement: Access-path-specific verification
The system SHALL support `direct-private` (default) and custom-only `corporate-routed`
access. Direct access SHALL resolve to APIM-reported private IPs. Corporate access SHALL
require network-owner evidence tying selected names and routing to the intended Internal
APIM, in addition to live binding, DNS, and TLS checks. An IP range SHALL NOT imply approval.

#### Scenario: Direct custom access
- **WHEN** custom endpoints resolve to APIM-reported private IPs and transport checks pass
- **THEN** direct-private access passes without a corporate-routing exception.

#### Scenario: Approved intermediary
- **WHEN** corporate-routed access has current network-owner evidence for the selected service and endpoints
- **THEN** different client-visible IPs are permitted, with attestation distinguished from measured checks.

#### Scenario: Unproven intermediary
- **WHEN** endpoints resolve to shared or other addresses but matching routing evidence is absent
- **THEN** readiness remains BLOCKED even when an HTTPS root request returns a response.

### Requirement: Generic endpoint evidence fields
`endpointValidationEvidence` SHALL extend `specs/00-network-foundation/contracts/validation-evidence.md`
with every exact base field: `validationType`, `status`, `owner`, `scope`,
`approvalReference`, `evidenceSummary`, and `timestampUtc`. Base fields SHALL remain
generic/redacted and non-empty strings. `validationType` SHALL be `apim-endpoint-access`;
`timestampUtc` SHALL be an ISO-8601 UTC validation-event timestamp.

#### Scenario: Conforming generic evidence
- **WHEN** an endpoint record includes all exact base fields with valid values
- **THEN** the base schema passes without treating schema conformance alone as readiness
  or authenticating operator approval.

#### Scenario: Generic evidence contract enforced
- **WHEN** custom evidence claims `pass` but omits a base field, uses an empty value or
  wrong field type, has an incorrect `validationType`, substitutes `timestamp` or
  `validationTimestamp` for `timestampUtc`, or has an invalid UTC timestamp
- **THEN** validation rejects it as readiness proof; foundation rejects missing or
  structurally invalid fields and Stage 2 preflight rejects the handoff even if overall
  status claims deployed.

### Requirement: Deployment endpoint evidence extension
Evidence SHALL include `apimServiceId`, `endpointMode`, `endpointAccessPath`,
`selectedHostnames`, and non-placeholder `validationReference`. Corporate routing SHALL
require `owner: network-owner` and separate non-placeholder `routingApprovalReference`.
Required extension values SHALL be non-empty strings except the hostname-map object.
Live context SHALL remain in untracked deployment inputs/handoffs and the customer
evidence store; committed examples SHALL remain redacted.

#### Scenario: Complete deployment evidence
- **WHEN** deployment evidence includes all required extension fields matching the service,
  mode, path, and exact gateway/developerPortal/management hostname map
- **THEN** its context matches the selected configuration, with corporate routing approval
  retained separately from the generic `approvalReference`.

#### Scenario: Invalid deployment evidence
- **WHEN** a required extension field or hostname-map entry is absent, empty, or of the
  wrong type, or corporate evidence lacks `owner: network-owner` or `routingApprovalReference`
- **THEN** foundation cannot advance readiness and Stage 2 rejects the handoff even if
  its overall status claims deployed.

### Requirement: Context-bound readiness handoff
The handoff SHALL identify mode, access path, selected hostnames, APIM service, exclusions,
and evidence. Custom readiness SHALL require complete, valid, matching evidence with
`status: pass`; non-pass, absent, or invalid evidence SHALL NOT advance readiness.
Stage 2 SHALL reject mismatched or invalid/non-pass custom handoffs and preserve existing
readiness checks. Legacy handoffs SHALL remain usable only with built-in/direct-private inputs.

#### Scenario: Custom readiness completed
- **WHEN** selected endpoint checks pass and matching evidence is recorded with other foundation prerequisites ready
- **THEN** foundation DNS and overall readiness become deployed.

#### Scenario: Changed selection or stale evidence
- **WHEN** the APIM service, selected names, or access path differs from the evidence context
- **THEN** the handoff is rejected and new validation is required.

#### Scenario: Non-pass validation evidence
- **WHEN** custom evidence has status `fail` or `blocked`, omits status, or supplies an invalid status
- **THEN** foundation readiness cannot become deployed and Stage 2 rejects the custom handoff.

#### Scenario: Legacy standard handoff
- **WHEN** a deployed legacy handoff is used without custom endpoint inputs
- **THEN** existing built-in/direct-private integration remains compatible.

### Requirement: Selected gateway integration
Integration request validation and generated client URLs SHALL use the selected gateway.
Explicit request URL overrides SHALL match its HTTPS host and configured API path and
SHALL use port 443, either implicitly or explicitly.
Stage 2 SHALL reference, not redeploy, APIM and SHALL validate APIM-to-Foundry behavior
separately from client-to-APIM connectivity.

#### Scenario: Custom gateway request
- **WHEN** integration runs with a validated custom handoff
- **THEN** its smoke request targets the custom gateway and verifies an actual approved-model response.

#### Scenario: Selected endpoint consumers
- **WHEN** an operator follows the inventoried project, portal, agent, and CI examples in custom mode
- **THEN** their APIM client settings and generated onboarding URLs use the selected gateway
  without a built-in fallback, API Center portal metadata uses the selected developer portal,
  and independent API Center/Foundry backend URLs and existing route suffixes are unchanged.

#### Scenario: Conflicting override
- **WHEN** a request override names a different gateway or incorrect API path
- **THEN** preflight fails rather than sending credentials to that destination.

#### Scenario: Non-default HTTPS port
- **WHEN** an override uses the selected hostname and API path but specifies port 8443 or any non-443 port
- **THEN** preflight rejects it before sending credentials; implicit or explicit port 443 is permitted.

### Requirement: Explicit operational limits
Guidance SHALL distinguish client endpoint exclusions from platform dependencies and
APIM-to-Foundry checks, describe operator-managed DNS/routing evidence and certificate
preservation, and keep customer names, IDs, certificate material, and credentials out
of committed examples and evidence.

#### Scenario: Custom-only organization
- **WHEN** an operator follows custom-mode instructions
- **THEN** the instructions identify legacy portal/SCM client exclusions, unchanged platform
  dependencies, private backend checks, and evidence needed before Stage 2 approval.
