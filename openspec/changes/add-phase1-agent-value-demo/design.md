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
- Support one POC account with repeatable project onboarding, preserving already deployed assets.

**Non-Goals:**

- Define the final multi-project or multi-environment production topology.
- Provision or redesign an enterprise AKS platform; an approved cluster is a prerequisite.
- Implement general-purpose user profiling, semantic memory, or enterprise retention governance.
- Replace APIM's existing gateway observability component.
- Treat the Foundry prompt agent and AKS-hosted agent as the same runtime or deployment.
- Implement the third, Foundry-managed hosted-agent runtime in this initial change.
- Provide per-agent backend authorization, business-unit account orchestration, or a new monitoring
  platform. The user approved gateway trust and reuse of approved shared monitoring infrastructure.

## Decisions

### 1. Separate shared services, account provisioning, and project onboarding

Use three independently invocable compositions, not three flags on an all-or-nothing deployment:

| Stage | Owns | Consumes; must not recreate |
|---|---|---|
| Shared services, before approval | POC Storage, Search, Cosmos, Key Vault if required, their new endpoints, agent Application Insights, sample corpus, baseline identities | Approved existing services, workspace, AMPLS, endpoint/DNS infrastructure |
| Account, after approval | One Foundry account, account-level network configuration/endpoint, approved model deployments | Shared-service output contract and existing network IDs |
| Project onboarding, repeatable | One project, its identity, connections, scoped RBAC, capability host | Existing account ID, shared-service IDs/endpoints, approved model deployments |

Extract reusable account/project logic from `infra/modules/foundry/main.bicep`; keep
`infra/envs/poc/foundry.bicep` as a compatible combined entry point for legacy callers. Add
separate POC compositions and stage-aware orchestration; do not route project onboarding through
the legacy combined module. Adding Project B must not redeploy the account, Project A, shared
services, or endpoints. Scope deployment names and role assignments to the selected project.
Validate this with one extra project, not a full agent demo per project or a project-fleet manager.

The shared-stage output contract carries full Storage, Search, Cosmos and applicable Key Vault
resource IDs, service endpoints, existing private-endpoint IDs and target subresources, subnet/DNS
ownership and association state, workspace/agent component/AMPLS IDs, and readiness by resource.
Account outputs add the account ID/endpoint/identity and account endpoint/DNS readiness. Project
outputs add project ID/endpoint/identity and capability readiness. These are ordinary deployment
outputs and parameters, not a new ownership-evidence system.

For shared Storage/Search/Cosmos, use the existing BYO resource-ID semantics and endpoint-reuse
flags in `infra/envs/poc/foundry.bicep:25-41`. An existing endpoint must have the intended target,
subresource, approval, and usable private route; mere existence is insufficient. Preserve endpoint
IDs in the handoff even where legacy modules emit an empty ID for skipped creation. Missing or
mismatched reuse inputs block activation instead of selecting the create branch. Move Key Vault
and its endpoint out of repeatable project creation: the existing combined module creates them
unconditionally. Reuse existing approved resources without retagging them, consistent with the
declared-ownership tagging contract.

Retain bare endpoint creation followed by separately owned DNS association, including Foundry
account DNS. Model provisioning is account-scoped and cannot require a project that has not yet
been created. Project creation precedes project-identity validation, connections/RBAC, and
capability activation; preflight must not require the new project's endpoint before creating it.
Foundry sender/tool readiness is not a prerequisite for creating the account/project needed to
evaluate those paths. Gate each stage on its actual prerequisites rather than an aggregate
platform-ready flag. Existing deployment approval/what-if checks remain in place.

A single deployment was rejected because approval would block shared work. Repeated calls to the
combined module were rejected because project onboarding would also manage account/shared assets.

### 2. Treat the service instances as shared Phase 1 resources

One Cosmos DB account, Storage account, Azure AI Search service, and agent Application Insights
component support the initial vertical slice. Resource names and tags identify the environment
and Phase 1 purpose, not a permanent organization-wide global scope.

Use one initial demonstration project and verify repeatable onboarding with a second project.
Resource reuse does not imply blanket data access: each project receives its own connections and
provider-managed persistence permissions; AKS keeps a separate application namespace. Shared
Search capacity and account-level identities are not a promise of strict project/tenant isolation.
Per-project service accounts and per-business-unit Foundry accounts are deferred, as are permanent
isolation, capacity, chargeback, and lifecycle design.

### 3. Keep APIM and agent Application Insights components separate

APIM retains its existing Application Insights component. Agent and validation telemetry uses a
second, workspace-based component connected to the supplied approved Log Analytics workspace.
Do not provision a fallback workspace in this POC. Require the approved shared AMPLS and its
private endpoint/DNS integration for the connected DNS domain; reuse rather than create a
competing scope. Resource associations for the workspace and relevant Application Insights
components must be approved by the monitoring owner. If the owner manages these associations,
emit the required association inputs and validate the completed result instead of deploying
unauthorized modifications.

Record ingestion/query access modes, resource public-access settings, permitted senders, and
private DNS routes. Preserve existing APIM ingestion and unrelated monitoring users; do not
change shared settings to make the demo pass. Validate AKS, Foundry-generated traces, and APIM
gateway telemetry separately. A private route from AKS is not proof that the Foundry runtime or
APIM logger can use the same path or identity mechanism. If a sender's supported private
telemetry path cannot be established, that runtime's observability remains BLOCKED without a
public-ingestion fallback. Existing APIM logger authentication must be assessed explicitly rather
than described as managed identity without evidence.

A single Application Insights component was rejected because gateway and application ownership,
alerts, sampling, and telemetry volume differ. Creating new workspace/AMPLS infrastructure when
reuse is unavailable was rejected to keep scope small; monitoring-owner onboarding is a prerequisite.

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

A Foundry-managed hosted agent is an approved roadmap direction for a follow-on to this demo,
not a third initial acceptance target. Preserve the relevant Chapter 08 material as separately
labelled follow-on guidance, not an AKS deployment instruction. The follow-on should reuse the
sample corpus, knowledge/tool contracts, shared assets where supported, and logical acceptance
suite. Its managed runtime identity, networking, memory ownership, telemetry, regional support,
and deployment adapter require their own feasibility review; AKS artifacts are not portable by
assumption. No hosted-agent deployment tasks are included in initial completion.

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

### 8. Use Entra at APIM and gateway identity at the backend

Expose one new OpenAPI-described read-only lookup API; keep the existing model API and its
subscription-key behavior unchanged. Use two tenant-approved API application registrations:
one stable audience for the APIM-facing tool API and a distinct backend audience. Application IDs,
tenant, token version, expected issuer/audience, and permitted principal IDs are deployment inputs,
not hard-coded identifiers. Tenant application provisioning/approval is an operator prerequisite;
do not grant tenant administration rights to agents.

APIM validates the Entra token signature, issuer/tenant, audience, and lifetime using
`validate-azure-ad-token`, then allows only the verified caller principal IDs for this one
operation. Pin the accepted application-token claims for the selected token version and reject
delegated user tokens. The AKS service account uses workload identity. Foundry uses the actual
managed identity supported by the pinned OpenAPI integration; do not assume an agent-specific
principal or authorize both account and project principals as a workaround. Disable subscription
requirements on the new tool API/product, remove key-check policies from that surface, and place
required auth/throttle policies at API/operation scope so keyless calls do not bypass them.

APIM replaces the inbound authorization credential with a backend-audience token acquired using
its own managed identity. The backend validates that token and permits only the approved APIM
principal; it does not accept original agent tokens. Backend deployment is a small separate
workload on the same approved AKS cluster, with a private endpoint/ingress route reachable by
APIM, its own service account, and no direct agent invocation permissions. This avoids a new
hosting platform while making gateway bypass observable in a negative test.

Use caller principal identity for authorization and throttling. Agent/project/correlation headers
are diagnostics only: strip any purported trusted identity headers from the request and, if
needed for logs, derive validated caller metadata at APIM. Agents sharing a Foundry principal
share its POC tool permission. Per-agent backend permissions and user-delegated/on-behalf-of
flows are explicitly deferred; they require a separately approved identity design.

Microsoft's current OpenAPI guidance and App Service integration guidance name different
Foundry identity scopes (see sources below). Task 1.5 pins the selected integration and verifies
its token claims without recording tokens. Until that evidence exists, Foundry tool integration
is BLOCKED, not permissioned speculatively. Entra audience configuration and private runtime
reachability must both work; success at token validation does not establish network reachability.

Direct backend fallback was rejected because it would bypass the value proposition and create
success paths that are not governed or observable.

### 9. Validate one deterministic vertical slice

The sample corpus contains stable, generic facts. The tool performs a read-only lookup of one
generic fixture identifier with a fixed response, explicit not-found response, and controlled
backend failure. Freeze its OpenAPI schema and fixture in task 1.2, not a choice of API versus
MCP or a customer action. The memory test records non-sensitive state,
resumes after a new session or AKS restart, and verifies continuity. Both agents run the same
logical test suite, with runtime-specific setup checks.

Broad exploratory chat testing was rejected as the release gate because it cannot provide
repeatable evidence.

## Feasibility Sources and Affected Surfaces

Inspected baseline code, not claims that the new compositions already exist:

| Surface | Existing evidence | Required change or limit |
|---|---|---|
| `infra/envs/poc/foundry.bicep:25-41,70-98` | Storage/Search/Cosmos BYO IDs and endpoint flags forwarded to combined module | Explicit shared output handoff; preserve legacy inputs/outputs |
| `infra/modules/foundry/main.bicep:79-139,242-281,331-362` | Account/project plus unconditional Key Vault/endpoints and project activation coupled together | Separate shared/account/project compositions and account-scoped models |
| `infra/modules/foundry/capability-host.bicep`, `cosmos-rbac.bicep`, `storage-rbac.bicep`, `project-connections.bicep` | Project-scoped capability/connection resources and workspace-derived persistence permissions | Reuse per-project logic; validate second-project non-interference and provider compatibility |
| `infra/modules/foundry/private-endpoint.bicep`, `infra/envs/poc/foundry-dns.bicep` | Bare endpoints, optional dependency endpoints, separate DNS deployment | Stage-owned endpoint reuse; no endpoint creation in project onboarding |
| `scripts/foundry/deploy.sh`, `preflight.sh`, `what-if.sh` | Existing execution approval and validation entry points | New stage-aware path without breaking existing combined callers or DNS scope rules |
| `infra/modules/apim/api.bicep:55-78,119-120` | Existing model API requires subscription key | Separate Entra tool API, not an in-place model-auth migration |
| `infra/modules/apim/observability.bicep:61-114` | Workspace-based APIM component and instrumentation-key logger | Preserve existing component; independently verify supported private ingestion/auth path |
| Chapters 06-08, new agent/tool workloads and validation adapters | Conceptual guidance, not executable dual-runtime evidence | Distinct AKS implementation, preserved hosted-agent follow-on, runtime-specific gates |

Authoritative references consulted for the proposed mechanisms:

- [Foundry resource/project architecture](https://learn.microsoft.com/en-us/azure/foundry/concepts/architecture):
  multiple projects per account are supported; connected services remain separately governed.
- [APIM Entra validation](https://learn.microsoft.com/en-us/azure/api-management/validate-azure-ad-token-policy)
  and [backend managed identity](https://learn.microsoft.com/en-us/azure/api-management/authentication-managed-identity-policy):
  inbound token validation and outbound credential acquisition are different boundaries.
- [Foundry OpenAPI tools](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/openapi)
  and [Foundry OpenAPI caller identity guidance](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-ai-foundry-openapi-tool):
  managed identity is supported, but the documented project-versus-account caller discrepancy
  requires the pinned integration check in task 1.5.
- [Azure Monitor Private Link](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/private-link-security)
  and [configuration](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/private-link-configure):
  use AMPLS resource associations plus private endpoint/DNS, and avoid competing scopes in a
  shared DNS domain.

## Requirement / Design / Task / Acceptance Traceability

Paths below are relative to this change. Each linked spec contains the named requirements and
their acceptance scenarios. Task IDs refer to `tasks.md`; decision numbers refer to this design.
This table is the coverage record, not a new runtime gate or a second task system.

| Spec and material requirements | Design / affected path | Tasks | Acceptance scenarios or evidence |
|---|---|---|---|
| [Shared platform](specs/phase1-shared-agent-platform/spec.md): Shared Phase 1 service foundation | 1-3; shared composition/monitoring | 2.1-2.8 | Deploy foundation before Foundry approval; Preserve APIM telemetry boundary; Resolve the agent telemetry workspace |
| Shared platform: Approval-gated platform activation | 1; account and project entry points | 2.6, 6.1-6.7, 6.9 | Block Foundry-dependent activation; Provision one account after approval; Continue after approval; Missing shared-resource handoff |
| Shared platform: Repeatable onboarding on one POC account | 1-2,7; project modules and legacy entry point | 6.3-6.9 | Onboard a second project; Repeat project onboarding; Retain the legacy deployment interface |
| Shared platform: Private and identity-based access | 1,3,6,8; endpoints/DNS, identities | 1.5-1.6, 2.3-2.5, 2.8, 5.1-5.3, 10.2-10.3 | Validate private connectivity; Reject embedded credentials |
| Shared platform: Reusable non-sensitive sample corpus; Phase 1 sharing is not a permanent global contract | 2,4; shared data and guidance | 3.1-3.4, 11.2-11.3 | Prepare grounding data; Document deferred scale decisions |
| [Grounding](specs/foundry-iq-grounding/spec.md): Foundry IQ knowledge base; Searchable ingestion pipeline | 4; Storage/Search ingestion | 1.3, 3.1-3.4, 7.1-7.5 | Create indexed knowledge source; Keep Foundry-dependent creation gated; Complete initial ingestion; Detect incomplete ingestion |
| Grounding: Grounded retrieval with citations; Shared knowledge contract for both agents | 4-5,9; knowledge interface and both runtimes | 7.4, 7.6, 8.1-8.2, 9.2, 10.1 | Retrieve an expected answer; Avoid unsupported claims; Publish the retrieval interface contract; Block an undefined retrieval interface; Compare grounding behavior |
| [Tooling](specs/governed-agent-tooling/spec.md): Approved tool invocation through APIM; Managed authentication and policy enforcement | 8; APIM/tool backend and caller tokens | 1.5, 4.1-4.6, 5.2, 9.3 | Invoke an approved tool; Prevent gateway bypass; Authorized/Unauthorized agent call; Backend trusts only the gateway identity; Verify the Foundry caller; Shared identity is not individual-agent authorization |
| Tooling: One deterministic read-only tool; Explicit tool failure behavior; End-to-end correlation | 8-9; lookup contract and errors | 1.2, 4.1, 4.4-4.6, 9.3, 10.4-10.5 | Reproduce the tool result; Backend operation fails; Trace a tool call |
| [Memory](specs/durable-agent-memory/spec.md): Prompt-agent managed persistence | 1,7; project connections/RBAC/capability | 6.4-6.8, 8.3 | Activate Foundry-managed persistence; Avoid speculative Foundry structures |
| Memory: AKS-agent application persistence; Memory ownership isolation | 7; project stores versus AKS namespace | 5.3, 6.5, 6.8, 9.4, 9.7 | Persist an AKS conversation; Preserve state after restart; Enforce separate write scopes |
| Memory: Minimum long-term memory demonstration | 7,9; continuity tests and scope | 8.3, 9.7, 10.1, 11.3 | Demonstrate continuity; Defer broader memory governance |
| [Delivery](specs/dual-agent-delivery/spec.md): Separate agent implementations; Common functional contract | 5,9; Foundry prompt and AKS deployments | 8.1-8.5, 9.1-9.7, 10.1, 11.5 | Identify both deployments; Update one implementation independently; Execute comparable workflow |
| Delivery: AKS deployment readiness; No hidden Foundry-hosting substitution | 5-6; cluster workload and guidance | 1.1, 5.1-5.5, 9.6, 11.1 | Deploy healthy AKS workload; Block without AKS prerequisite; Report runtime location |
| Delivery: Foundry-managed hosted agent is a follow-on | 5; roadmap only | 11.1, 11.3 | Complete the initial two-agent POC; Plan the third runtime |
| [Observability](specs/agent-observability-validation/spec.md): Separate APIM and agent telemetry components; Reuse approved private monitoring connectivity | 3; approved AMPLS/workspace and both components | 1.6, 2.2-2.4, 2.8, 4.5, 8.4, 9.5, 10.4 | Route gateway telemetry; Route agent telemetry; Reuse the shared monitoring path; Missing approval or unsupported telemetry route |
| Observability: Correlated dependency telemetry; Repeatable end-to-end validation | 3,9; runtime-specific validation adapters | 10.1-10.5, 11.5 | Investigate one transaction; Pass the value demonstration; Fail closed on incomplete evidence |
| Observability: Safe validation evidence | 9; logs/evidence | 8.4, 9.5, 10.6, 11.4 | Publish validation evidence |

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
- **[Shared Foundry tool identity lacks individual-agent isolation]** → Accept common permission
  for the single POC operation; verify the actual principal, never authorize by diagnostic headers.
- **[Shared AMPLS changes disrupt other senders]** → Require owner approval and sender-specific
  validation; block instead of modifying global DNS/access modes or creating another scope.

## Migration Plan

1. Deploy or reuse shared Cosmos DB, Storage, Search, applicable Key Vault, and agent Application
   Insights; consume approved existing workspace/AMPLS and record the shared-resource handoff.
2. Complete bare private endpoints and the existing staged DNS association process; validate
   identity-based data-plane access from approved network locations.
3. Upload the generic sample corpus and record its expected document identifiers and test
   questions.
4. Prepare the AKS namespace, workload identity binding, registry access, private dependency
   routes, and deployment pipeline against an approved cluster.
5. After approval, provision or validate the single Foundry account and account-level networking
   and models. Onboard the first project against that account and shared assets, then its
   connections, scoped RBAC, and capability host. Verify a second project without replacing the first.
6. Create and ingest the Foundry IQ knowledge source and knowledge base; validate retrieval and
   citations.
7. Deploy and validate the prompt agent.
8. Build, deploy, and validate the independent AKS-hosted agent.
9. Run the shared end-to-end suite and publish redacted evidence.

Rollback removes the two agent deployments, Foundry IQ objects, application-owned AKS memory
data, and agent-specific role assignments in reverse order. Shared service accounts and the
sample corpus remain unless explicitly approved for removal. Foundry-managed persistence is not
manually modified during rollback; capability-host and project teardown follows the provider's
supported lifecycle. Project rollback cannot delete shared resources, account-level models, or
other projects. Shared monitoring is not removed or reconfigured by demo rollback.

## Stage-Specific Prerequisites and Readiness

Approved design decisions are gateway trust, three lifecycle boundaries, one POC account with
repeatable project onboarding, shared monitoring reuse, and two initial runtimes plus a deferred
managed hosted-agent follow-on. These are not open architecture questions.

| Gate | Owning task | Blocks until evidence is available |
|---|---|---|
| Approved AKS cluster, registry, namespace and private ingress reachable by callers/APIM | 1.1, 5.1 | AKS/tool deployment, not independent shared-service provisioning |
| Tenant API applications and verified Foundry OpenAPI caller/audience for the pinned runtime | 1.5 | Foundry tool integration; offline policy work may proceed, no claim of verified caller identity |
| Shared workspace/AMPLS owner approval and supported private telemetry path per sender | 1.6, 2.8 | Affected telemetry integration and complete demo acceptance |
| Foundry account/project and regional model approvals, compatible provider/API version | 1.3, 6.1 | Account provisioning and dependent activation |
| Pinned Foundry IQ retrieval endpoint/schema/audience usable by both runtimes | 7.6 | Agent retrieval implementation/integration, not pre-approval corpus upload |

Actual IDs and approved model versions are deployment inputs. Unsupported identity, telemetry, or
retrieval behavior is a feasibility blocker for the affected integration, not permission to
substitute another architecture. Record that blocker, resolve it before implementing the dependent
work, and seek approval if the contract must change. No live gate is claimed passed by this
specification update; the full integration handoff remains blocked while these checks are unresolved.
