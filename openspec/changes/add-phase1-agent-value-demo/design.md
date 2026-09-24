## Context

See `proposal.md` for motivation. The repository already contains:

- a private Foundry foundation with independently reusable Cosmos DB, Storage, and Azure AI
  Search dependencies, project connections, RBAC, and an Agents capability host;
- a staged APIM foundation and deferred Foundry integration with APIM-specific Application
  Insights;
- conceptual Chapter 06 and Chapter 07 flows for Foundry IQ and prompt agents; and
- a Chapter 08 hosted-agent flow that deploys into Foundry-managed Container Apps rather than
  the newly approved AKS target.

The Foundry project is approval-gated, but the supporting services can be prepared first. The
design must preserve the existing Foundry private-endpoint/DNS staging and APIM
foundation/integration split while adding a runnable vertical slice.

## Goals / Non-Goals

**Goals:**

- Produce two independently deployable agents with a common value-demonstration contract.
- Allow secure shared services, sample data, AKS prerequisites, and observability to be prepared
  before Foundry approval.
- Use current Foundry IQ knowledge-base and knowledge-source concepts rather than relying only on
  the older chapter terminology of a knowledge index.
- Make every required dependency and readiness gate observable and repeatable.

**Non-Goals:**

- Define the final multi-project or multi-environment production topology.
- Provision or redesign an enterprise AKS platform; an approved cluster is a prerequisite.
- Implement general-purpose user profiling, semantic memory, or enterprise retention governance.
- Replace APIM's existing gateway observability component.
- Treat the Foundry prompt agent and AKS-hosted agent as the same runtime or deployment.

## Decisions

### 1. Use a two-stage deployment boundary

The pre-approval stage deploys the shared service accounts, private connectivity, agent
observability, sample corpus, and non-Foundry identities that can be validated independently.
The activation stage creates Foundry project connections, RBAC, capability host, Foundry IQ
objects, and agents.

This preserves useful progress without fabricating Foundry-managed child resources. A single
all-or-nothing deployment was rejected because Foundry approval would block every resource and
make independent infrastructure validation impossible.

### 2. Treat the service instances as shared Phase 1 resources

One Cosmos DB account, Storage account, Azure AI Search service, and agent Application Insights
component support the initial vertical slice. Resource names and tags identify the environment
and Phase 1 purpose, not a permanent organization-wide global scope.

Per-project dedicated resources were rejected for Phase 1 because only one initial Foundry
project and one AKS agent are required. Permanent sharing was also rejected because isolation,
capacity, chargeback, and lifecycle decisions require Phase 2 analysis.

### 3. Keep APIM and agent Application Insights components separate

APIM retains its existing Application Insights component. Agent and validation telemetry uses a
second component, preferably workspace-based and connected to the existing approved Log
Analytics workspace when policy and access boundaries permit.

A single Application Insights component was rejected because gateway and application ownership,
alerts, sampling, and telemetry volume differ. Separate Log Analytics workspaces are not required
for Phase 1 unless policy prevents workspace reuse.

### 4. Use Blob Storage as the first indexed Foundry IQ knowledge source

The pre-approval stage uploads a versioned generic sample corpus to a dedicated container. After
approval, Foundry IQ creates a knowledge base and an indexed knowledge source backed by that
container. The ingestion configuration uses supported chunking, vectorization, semantic
configuration, and refresh behavior.

Manually maintaining a parallel custom RAG pipeline was rejected because the value proposition
is specifically Foundry IQ. An existing-index source can be supported later, but the initial
path should exercise managed ingestion from source documents.

### 5. Share the knowledge contract, not the agent runtime

Both agents use the same knowledge base, APIM tool contract, sample questions, expected
citations, and memory-continuity tests. The prompt agent is configured and versioned in Foundry.
The code-based agent is built as a container image and deployed to AKS.

Deploying both as Foundry-managed agents was rejected because the approved requirement explicitly
calls for an AKS implementation. Treating the AKS agent as a mere proxy to the prompt agent was
rejected because it would not demonstrate an independent code-based implementation.

### 6. Consume an approved AKS cluster rather than provision the enterprise cluster

The change accepts the approved cluster, namespace, container registry, ingress or internal
endpoint, workload-identity issuer, and network integration as prerequisites. It adds only the
agent workload, service account identity binding, configuration, policies required for the
agent, and deployment validation.

Provisioning a new AKS platform was rejected as disproportionate to the Phase 1 agent slice and
would introduce unrelated cluster lifecycle, fleet, upgrade, and platform-governance scope.

### 7. Separate Cosmos DB ownership boundaries

The prompt agent uses Standard Agent Setup: Foundry project connections, project identity RBAC,
and the Agents capability host manage the expected thread, message, and agent-entity stores.
The AKS agent uses its workload identity and an application-owned database/container namespace.
Neither identity writes into the other's structures.

Sharing the account keeps Phase 1 small while separate write scopes prevent schema coupling.
Having the AKS agent write directly to Foundry-managed containers was rejected because those
schemas and lifecycle belong to Foundry Agent Service.

### 8. Route all protected tool calls through APIM

Each agent receives only the APIM tool endpoint and approved identity configuration. APIM owns
caller validation, authorization, throttling, policy, backend routing, and gateway telemetry.
Correlation context is propagated through APIM to the backend.

Direct backend fallback was rejected because it would bypass the value proposition and create
success paths that are not governed or observable.

### 9. Validate one deterministic vertical slice

The sample corpus contains stable, generic facts. The approved tool performs a safe,
deterministic operation with a verifiable response. The memory test records non-sensitive state,
resumes after a new session or AKS restart, and verifies continuity. Both agents run the same
logical test suite, with runtime-specific setup checks.

Broad exploratory chat testing was rejected as the release gate because it cannot provide
repeatable evidence.

## Risks / Trade-offs

- **[Foundry IQ APIs or schemas change during preview]** → Pin supported API versions, isolate
  Foundry IQ provisioning behind a focused module or script, and validate against current
  provider documentation before implementation.
- **[Private Foundry endpoints cannot be reached from the validation runner]** → Run live
  data-plane validation from an approved VNet-connected runner and keep management-plane checks
  separate.
- **[Shared services obscure per-agent cost and capacity]** → Add agent/runtime dimensions to
  telemetry and tags; defer permanent chargeback architecture to Phase 2.
- **[AKS cluster prerequisites are unavailable]** → Mark AKS readiness blocked while allowing
  pre-approval shared-resource work and prompt-agent work to retain their independent status.
- **[Cosmos DB permissions become overly broad]** → Use separate identities and the narrowest
  available data-plane scopes; validate effective assignments before activation.
- **[Application Insights captures sensitive prompts or document content]** → Default to
  metadata, identifiers, timings, status, and redacted exception details; require explicit
  approval for content capture.
- **[The current chapters contain stale SDK examples]** → Treat official current APIs and
  successful executable validation as authoritative, then update chapter examples to match.

## Migration Plan

1. Deploy or reuse the shared Cosmos DB, Storage, Azure AI Search, agent Application Insights,
   and approved Log Analytics workspace integration.
2. Complete bare private endpoints and the existing staged DNS association process; validate
   identity-based data-plane access from approved network locations.
3. Upload the generic sample corpus and record its expected document identifiers and test
   questions.
4. Prepare the AKS namespace, workload identity binding, registry access, private dependency
   routes, and deployment pipeline against an approved cluster.
5. After Foundry approval, deploy or validate the project, project connections, scoped RBAC, and
   capability host.
6. Create and ingest the Foundry IQ knowledge source and knowledge base; validate retrieval and
   citations.
7. Deploy and validate the prompt agent.
8. Build, deploy, and validate the independent AKS-hosted agent.
9. Run the shared end-to-end suite and publish redacted evidence.

Rollback removes the two agent deployments, Foundry IQ objects, application-owned AKS memory
data, and agent-specific role assignments in reverse order. Shared service accounts and the
sample corpus remain unless explicitly approved for removal. Foundry-managed persistence is not
manually modified during rollback; capability-host and project teardown follows the provider's
supported lifecycle.

## Open Questions

- Which existing approved AKS cluster and ingress pattern will host the Phase 1 code-based agent?
- Which safe, deterministic APIM-managed tool will be used for the acceptance test?
- Which supported embedding and query-planning model deployments will be approved in the target
  region?
