## Purpose

Defines durable, isolated conversation persistence for the Foundry prompt agent and the
AKS-hosted code-based agent using the shared Phase 1 Cosmos DB account.

## ADDED Requirements

### Requirement: Prompt-agent managed persistence
The Foundry prompt agent SHALL use Standard Agent Setup project connections, project identity
RBAC, and the Agents capability host so Foundry Agent Service can maintain its required thread,
message, and agent-state data in Cosmos DB.

#### Scenario: Activate Foundry-managed persistence
- **WHEN** the project connections, pre-authorized RBAC assignments, and capability host are ready
- **THEN** Foundry can create and use its managed persistence structures without account keys

#### Scenario: Avoid speculative Foundry structures
- **WHEN** the Foundry project identity or capability host is not available
- **THEN** the pre-approval deployment does not manually create containers using Foundry-managed names

### Requirement: AKS-agent application persistence
The AKS-hosted agent SHALL use its workload identity to store application-owned conversation
state in a database or container namespace separate from Foundry-managed persistence structures.

#### Scenario: Persist an AKS conversation
- **WHEN** the AKS-hosted agent processes a conversation turn
- **THEN** it can write and retrieve the required conversation state using its workload identity

#### Scenario: Preserve state after restart
- **WHEN** the AKS workload restarts and a client resumes a known conversation
- **THEN** the agent reloads the persisted state and continues the conversation without relying on pod-local storage

### Requirement: Memory ownership isolation
The prompt agent and AKS-hosted agent SHALL NOT write directly into each other's managed or
application-owned Cosmos DB structures.

#### Scenario: Enforce separate write scopes
- **WHEN** RBAC assignments are evaluated for either agent identity
- **THEN** each identity has write access only to the data structures it owns for the Phase 1 scenario

### Requirement: Minimum long-term memory demonstration
Phase 1 SHALL demonstrate durable conversation continuity and SHALL NOT claim completion of a
general user-profile or semantic-memory architecture.

#### Scenario: Demonstrate continuity
- **WHEN** a validation conversation records a stable, non-sensitive preference or prior decision and is later resumed
- **THEN** the agent can use the persisted information and the validation evidence identifies the stored conversation

#### Scenario: Defer broader memory governance
- **WHEN** Phase 1 is declared complete
- **THEN** cross-project memory, profile inference, retention policy, legal hold, and enterprise deletion workflows remain explicitly deferred unless separately approved
