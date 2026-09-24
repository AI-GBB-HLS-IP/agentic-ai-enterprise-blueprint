## Purpose

Defines two separate but behaviorally comparable Phase 1 agent implementations: a Foundry prompt
agent and a code-based agent deployed to an approved AKS cluster.

## ADDED Requirements

### Requirement: Separate agent implementations
The solution SHALL deliver one Microsoft Foundry prompt agent and one independently packaged
code-based agent deployed as an AKS workload.

#### Scenario: Identify both deployments
- **WHEN** Phase 1 deployment completes
- **THEN** the validation report identifies distinct prompt-agent and AKS-agent deployment identities, versions, and endpoints

#### Scenario: Update one implementation independently
- **WHEN** only one agent implementation changes
- **THEN** it can be versioned and redeployed without replacing the other implementation

### Requirement: Common functional contract
Both agents SHALL answer grounded questions through Foundry IQ, invoke approved tools through
APIM, persist conversation state in Cosmos DB, and emit correlated telemetry.

#### Scenario: Execute comparable workflow
- **WHEN** the approved end-to-end test request is submitted to each agent
- **THEN** each agent performs grounding, tool invocation, memory persistence, and telemetry emission according to the same acceptance criteria

### Requirement: AKS deployment readiness
The code-based agent SHALL be deployable to an approved AKS cluster with workload identity,
private dependency access, health probes, bounded resource requests and limits, and repeatable
image deployment.

#### Scenario: Deploy healthy AKS workload
- **WHEN** the approved cluster, namespace, identity, image registry, network access, and configuration are available
- **THEN** the agent reaches its declared ready state and can be invoked through the approved endpoint

#### Scenario: Block without AKS prerequisite
- **WHEN** an approved AKS cluster or required cluster integration is unavailable
- **THEN** AKS-agent readiness remains blocked and the deployment does not report a successful hosted-agent outcome

### Requirement: No hidden Foundry-hosting substitution
The AKS-hosted agent SHALL run on AKS and SHALL NOT be represented as the Foundry-managed Hosted
Agent deployment described by the current Chapter 08 flow.

#### Scenario: Report runtime location
- **WHEN** deployment evidence is generated
- **THEN** it identifies AKS as the code-based agent runtime and Foundry as the prompt-agent and knowledge-service platform
