## Why

The blueprint can provision the supporting platform, but it does not yet define a single
deployable Phase 1 outcome that proves business value across grounding, governed tool use,
durable memory, AKS hosting, and observability. Foundry approval is still pending, so the work
also needs an explicit boundary between infrastructure that can be prepared now and integration
that must wait for the Foundry project.

## What Changes

- Define one Phase 1 vertical slice with two separate implementations:
  - a Microsoft Foundry prompt agent; and
  - a code-based agent packaged and deployed to AKS.
- Require both agents to use the same Foundry IQ knowledge base, call governed tools through
  APIM, persist durable conversation state in Cosmos DB, and emit correlated telemetry.
- Prepare one shared Phase 1 set of Cosmos DB, Storage, Azure AI Search, agent Application
  Insights, Log Analytics, private-networking, identity, and RBAC resources while Foundry
  approval is pending.
- Keep the existing APIM Application Insights component dedicated to gateway telemetry and add a
  separate shared component for agent and application telemetry.
- Upload a generic, non-sensitive sample corpus before Foundry approval, but defer Foundry IQ
  knowledge-source creation, ingestion, indexing, and agent connection until Foundry is
  available.
- Defer speculative Foundry-managed Cosmos databases and containers until the Foundry project,
  project identity, connections, RBAC assignments, and capability host can be configured.
- Add repeatable end-to-end validation for grounded answers and citations, APIM tool calls,
  conversation persistence, AKS deployment, managed identity, private connectivity, and
  correlated traces.
- Explicitly defer the permanent multi-project sharing, isolation, capacity, chargeback,
  retention, and dedicated-versus-shared resource model to Phase 2.

## Capabilities

### New Capabilities

- `phase1-shared-agent-platform`: Defines the shared pre-Foundry resources, staged activation
  boundary, private connectivity, identities, and baseline access controls.
- `foundry-iq-grounding`: Defines the sample corpus, knowledge source, knowledge base, ingestion,
  retrieval, grounding, and citation behavior.
- `governed-agent-tooling`: Defines how both agents discover and invoke approved tools through
  APIM with managed authentication and gateway policy enforcement.
- `durable-agent-memory`: Defines Foundry-managed prompt-agent persistence and application-owned
  AKS-agent memory without cross-writing into each other's data structures.
- `dual-agent-delivery`: Defines the separate Foundry prompt-agent and AKS-hosted-agent
  implementations and their common functional contract.
- `agent-observability-validation`: Defines telemetry separation, correlation, end-to-end
  validation, and evidence required to demonstrate the Phase 1 value proposition.

### Modified Capabilities

None. The repository has no canonical OpenSpec capability specifications; related requirements
currently live in legacy chapter and feature-spec artifacts that implementation will align.

## Impact

- Affects Chapters 06-08 for Foundry IQ, prompt-agent, and hosted-agent guidance; Chapter 08 must
  add or replace the current Foundry-managed Container Apps path with the approved AKS delivery
  target for this Phase 1 implementation.
- Builds on the Chapter 01 Foundry account/project, dependent-resource, private-endpoint, RBAC,
  project-connection, and capability-host modules without changing their staged DNS contract.
- Builds on the staged Chapter 02 APIM foundation and deferred Foundry integration; APIM remains
  the governance boundary for tool calls and retains its dedicated observability component.
- Adds or affects AKS workload identity, container registry, Kubernetes deployment, network
  policy, secrets/configuration, health probes, and deployment-pipeline artifacts.
- Adds sample-data, Foundry IQ configuration, agent source, memory integration, telemetry,
  validation, and evidence artifacts. All committed examples must use generic names and
  non-sensitive data.
- Tracks implementation in GitHub issue #83 on branch
  `spec/phase1-agent-value-demo`.
