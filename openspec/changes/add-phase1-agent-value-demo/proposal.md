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
- Keep a Foundry-managed hosted agent as a follow-on to the same demo, not a third runtime
  required for initial acceptance. Reuse the knowledge, tool, and acceptance contracts where
  supported; verify its identity, networking, persistence, and telemetry separately before adding it.
- Require both agents to use the same Foundry IQ knowledge base, call governed tools through
  APIM, persist durable conversation state in Cosmos DB, and emit correlated telemetry.
- Prepare one shared Phase 1 set of Cosmos DB, Storage, Azure AI Search, agent Application
  Insights, Log Analytics, private-networking, identity, and RBAC resources while Foundry
  approval is pending.
- Separate shared-service provisioning, approval-gated Foundry account provisioning, and
  repeatable project onboarding. Use one account for this POC, initially one project with a
  second-project onboarding check; additional projects must reuse the deployed shared assets
  without redeploying the account or other projects.
- Require explicit resource-ID and private-endpoint handoffs between stages, including Key Vault
  where used. Missing reuse inputs block activation rather than silently creating another set.
- Keep the existing APIM Application Insights component dedicated to gateway telemetry and add a
  separate shared component for agent and application telemetry.
- Reuse an approved Log Analytics workspace and Azure Monitor Private Link Scope (AMPLS) with
  centrally owned private endpoints/DNS. If these are unavailable or cannot be associated safely,
  block the monitoring stage instead of creating a competing shared-network monitoring topology.
- Protect one read-only deterministic OpenAPI tool with Entra tokens at APIM; the backend trusts
  APIM's managed identity. Do not require subscription keys for the new tool API or change the
  existing model API's authentication. Shared Foundry caller identities do not provide per-agent
  authorization, and diagnostic agent IDs are not trusted credentials.
- Upload a generic, non-sensitive sample corpus before Foundry approval, but defer Foundry IQ
  knowledge-source creation, ingestion, indexing, and agent connection until Foundry is
  available.
- Defer speculative Foundry-managed Cosmos databases and containers until the Foundry project,
  project identity, connections, RBAC assignments, and capability host can be configured.
- Add repeatable end-to-end validation for grounded answers and citations, APIM tool calls,
  conversation persistence, AKS deployment, managed identity, private connectivity, and
  correlated traces.
- Explicitly defer the permanent multi-project sharing, isolation, capacity, chargeback,
  retention, per-business-unit accounts, and dedicated-versus-shared resource model to Phase 2.
  Maintain a compact requirement/design/task/acceptance matrix in the design, not a separate
  governance system.

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
  add the approved AKS delivery path for initial acceptance and retain separately labelled
  Foundry-managed hosted-agent material for the follow-on.
- Builds on the Chapter 01 Foundry account/project, dependent-resource, private-endpoint, RBAC,
  project-connection, and capability-host modules, extracting separate lifecycle entry points
  while preserving their staged DNS contract and the legacy combined deployment interface.
- Builds on the staged Chapter 02 APIM foundation and deferred Foundry integration; APIM remains
  the governance boundary for tool calls and retains its dedicated observability component.
- Adds or affects AKS workload identity, container registry, Kubernetes deployment, network
  policy, secrets/configuration, health probes, and deployment-pipeline artifacts.
- Adds sample-data, Foundry IQ configuration, agent source, memory integration, telemetry,
  validation, and evidence artifacts. All committed examples must use generic names and
  non-sensitive data.
- Tracks implementation in GitHub issue #83 on branch
  `spec/phase1-agent-value-demo`.

## Scope and Readiness

The POC demonstrates both initial runtimes against one small sample corpus, one knowledge base,
one safe lookup operation, and durable conversation resume. Multiple projects mean repeatable
onboarding on one account, not a claim of production tenant isolation or a full demo in every
project. The Foundry-managed hosted-agent follow-on and business-unit topology do not gate
initial acceptance.

The design records inspected code paths, platform references, traceability, and stage-specific
gates. Foundry runtime identity, private telemetry, model availability, and retrieval-interface
evidence must be verified for the selected versions; structural validation alone does not make
these unresolved integrations implementation-ready.
