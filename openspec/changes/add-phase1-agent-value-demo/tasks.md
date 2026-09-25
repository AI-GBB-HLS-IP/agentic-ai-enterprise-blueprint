## 1. Confirm Phase 1 Inputs and Contracts

Initial acceptance covers a Foundry prompt agent and AKS agent, one account, one shared sample
knowledge base and read-only lookup tool, plus a second-project onboarding check. The
Foundry-managed hosted-agent runtime is a separately scoped follow-on, not an unchecked initial
implementation requirement. The design's traceability matrix is the single coverage record.

- [ ] 1.1 Record the approved AKS cluster resource ID, namespace, ingress pattern, workload-identity issuer, and container registry inputs in the deployment contract, and verify missing values produce a BLOCKED prerequisite result rather than a success-shaped default
- [ ] 1.2 Freeze one OpenAPI-described read-only lookup operation over generic fixture data, with a stable identifier input, fixed success response, explicit not-found and controlled backend-failure behavior, and verify the same contract/fixture drives both agent acceptance adapters
- [ ] 1.3 Record approved chat, embedding, and Foundry IQ query-planning model deployments and regional availability, and verify preflight fails closed when approval or capacity evidence is absent
- [ ] 1.4 Update the relevant legacy feature specs and Chapters 06-08 to link issue #83 and this OpenSpec change, and verify the documented scope distinguishes the initial prompt/AKS agents, repeatable projects on one account, hosted-agent follow-on, and deferred business-unit/production topology
- [ ] 1.5 Record tenant-approved tool and backend API application audiences, token version/issuer, allowed principal IDs, and the selected Foundry OpenAPI integration/API version; verify its actual caller claims using redacted evidence before permissioning Foundry, and report unverified identity/audience or unavailable tenant approvals as BLOCKED without assuming account/project identities are interchangeable
- [ ] 1.6 Record approved workspace, AMPLS, private endpoint/DNS ownership, required monitoring associations, and each sender's supported authentication/private route; verify owner approval and classify unresolved AKS, Foundry, and APIM paths independently as BLOCKED rather than creating fallback monitoring infrastructure

## 2. Build the Pre-Approval Shared Platform

- [ ] 2.1 Extract reusable shared-resource modules and add a pre-approval composition for Cosmos DB, Storage, Search, and applicable Key Vault, preserving explicit create-versus-reference ownership and adding Key Vault reuse rather than unconditional project-stage creation; verify compiled output contains no Foundry account/project/capability and what-if does not replace supplied resources
- [ ] 2.2 Add or reuse the agent-specific workspace-based Application Insights component, separate from APIM, bound only to the approved supplied workspace from task 1.6; verify outputs identify both telemetry boundaries and missing approval/workspace yields BLOCKED with no workspace fallback
- [ ] 2.3 Add or reuse bare private endpoints for shared Cosmos DB, Storage, Search, and applicable Key Vault, while reusing the approved AMPLS endpoint for monitoring; verify target ID/subresource/approval and private route, no duplicate endpoints or AMPLS, and no Foundry endpoint before the account stage
- [ ] 2.4 Preserve later DNS association for newly created service endpoints and independently skipped supplied full endpoint IDs; add or request owner-managed AMPLS resource associations and DNS integration from task 1.6, and verify association readiness without overwriting shared zones, access modes, or unrelated monitoring routes
- [ ] 2.5 Add baseline operational identities and least-privilege management/data-plane role assignments that do not depend on a Foundry project, and verify no developer, validation, or runtime identity receives broad Owner, Contributor, or unnecessary data-owner access
- [ ] 2.6 Publish the shared-stage handoff of full service/Key Vault IDs, endpoints, endpoint target/subresource/approval and DNS state, workspace/component/AMPLS IDs, and ownership/reuse choices; verify existing, deployed, pending, blocked, and failed readiness is distinct, skipped-create endpoints retain their supplied IDs, and missing required reuse data blocks later activation
- [ ] 2.7 Add module contract tests for shared-resource reuse, separate agent observability, private-endpoint flags, staged DNS inputs, and approval gates, and verify the targeted infrastructure tests pass
- [ ] 2.8 After tasks 1.6 and 2.2-2.4, validate each available sender's private telemetry ingestion and authorized query route into its intended component, with no public fallback or disruption of APIM telemetry; verify unsupported/unavailable runtime paths remain named BLOCKED gates and repeat Foundry-specific checks after activation

## 3. Prepare the Foundry IQ Sample Corpus

- [ ] 3.1 Create a small generic non-sensitive sample document corpus with stable source identifiers and expected factual answers, and verify the repository confidentiality scan passes
- [ ] 3.2 Add an idempotent managed-identity upload process for a dedicated Phase 1 Storage container, and verify repeated uploads produce the declared document set without embedding account keys
- [ ] 3.3 Define grounding test cases for answerable questions, unanswerable questions, expected source references, and minimum relevance behavior, and verify each expected answer maps to a committed generic source document
- [ ] 3.4 Add pre-approval Storage validation for private DNS, private reachability, identity-based list/read access, and sample-corpus completeness, and verify failures keep corpus readiness false

## 4. Prepare Governed APIM Tool Access

- [ ] 4.1 Implement the task 1.2 lookup backend as a separate small AKS workload/service using the approved cluster/registry/private ingress from tasks 1.1 and 5.1; validate backend-audience Entra tokens and allow only APIM's managed-identity principal, and verify fixture success/not-found/failure plus rejection of direct agent tokens
- [ ] 4.2 Add a separate Entra-protected APIM OpenAPI tool API with subscription requirements disabled and API/operation-scoped policies validating tenant, issuer, audience, expiry, application-token type, and the task 1.5 approved principal IDs; verify keyless authorized calls and preserve the existing subscription-key model API and staged deployment boundary
- [ ] 4.3 Ensure agent runtime configuration exposes only the APIM endpoint for the protected tool, and verify a repository test fails if the protected backend endpoint is configured directly
- [ ] 4.4 Add principal-based throttling, timeout/error mapping and correlation propagation, replace inbound authorization with an APIM managed-identity backend-audience token, and strip spoofable trusted-identity headers; verify missing/expired/wrong-tenant/wrong-audience/unapproved tokens are rejected, headers cannot elevate permissions, and backend failures never produce success
- [ ] 4.5 Extend APIM validation evidence for the selected tool operation and correlation identifier, and verify gateway telemetry remains in the APIM-dedicated Application Insights component
- [ ] 4.6 After AKS backend deployment and verified Foundry caller configuration, test both agent callers through APIM and direct-backend denial, and verify a shared Foundry principal has only the common POC operation permission with no per-agent authorization claim or key fallback

## 5. Prepare the AKS Delivery Foundation

- [ ] 5.1 Add prerequisite validation for the approved AKS cluster, namespace, OIDC/workload-identity configuration, registry access, network routes, private DNS, and ingress pattern, and verify each missing prerequisite produces a named BLOCKED gate
- [ ] 5.2 Add an AKS workload identity and federated service-account binding scoped to the agent namespace, and verify token acquisition works without Kubernetes secrets containing Azure credentials
- [ ] 5.3 Add least-privilege AKS-agent data-plane permissions for its application-owned Cosmos DB scope, Foundry IQ, and supported telemetry ingestion, and register its principal in the tool API allowlist rather than assuming an Azure management role grants APIM invocation; verify effective permissions exclude Foundry-managed Cosmos structures and direct tool-backend access
- [ ] 5.4 Add the container build and registry publication pipeline for the code-based agent with immutable image versioning, and verify the built image can be pulled by the approved cluster identity
- [ ] 5.5 Add parameterized Kubernetes deployment, service, configuration, health probes, resource requests/limits, disruption behavior, and network policy artifacts, and verify server-side manifest validation succeeds against the target cluster version

## 6. Provision One Account and Onboard Projects

- [ ] 6.1 Add stage-aware preflight for approval, task 2.6 shared-resource handoff, provider/API support, model approvals, and network scope; verify account provisioning does not require a not-yet-created project endpoint, while project activation requires the resolved project identity after creation and never defaults missing shared IDs to create-new
- [ ] 6.2 Extract account provisioning into an independently invocable composition owning one account, its account-level endpoint/networking and approved model deployments; verify it consumes the shared handoff, deploys no project or shared service, retains separate DNS association, and emits account ID/endpoint/identity and network readiness
- [ ] 6.3 Add a project-onboarding entry point taking the existing account ID and shared handoff, creating or updating only the selected project before activation, and verify project-scoped deployment names and outputs identify its ID/endpoint/identity without account/shared-resource/endpoint declarations
- [ ] 6.4 Reuse or extend project connections for Cosmos DB, Storage, and Search with managed authentication after task 6.3, and verify every connection references the task 2.6 resource ID in its actual scope
- [ ] 6.5 Apply project-identity persistence RBAC after project creation and before capability activation, and verify least-privilege project-derived scopes preserve existing projects' grants and do not include the AKS-owned Cosmos namespace
- [ ] 6.6 Activate the selected project's Agents capability host only after tasks 6.4-6.5 and approved private connectivity, and verify Foundry can provision its managed persistence without account keys
- [ ] 6.7 Verify the selected new project's managed persistence structures are absent before first activation and provider-created afterward, without requiring other projects' structures to be absent or manually creating Foundry-owned containers
- [ ] 6.8 Add a second-project onboarding and same-project rerun test using the original account/shared IDs; verify stable IDs, no duplicate endpoints, no replacement of Project A, unchanged existing grants/data, project-specific persistence scopes, and continued Project A operation without repeating the full agent demo in Project B
- [ ] 6.9 Preserve the legacy combined entry point's documented parameters/outputs/defaults and execution approval checks while introducing explicit shared/account/project commands; verify legacy compile/contract regressions, project-only what-if, and rollback that cannot delete shared assets, account models, or another project

## 7. Create and Validate Foundry IQ

- [ ] 7.1 Add idempotent automation for the indexed Blob Storage knowledge source using the approved identity and sample container, and verify the resulting object references the intended Storage resource and container
- [ ] 7.2 Add idempotent automation for the knowledge base with approved retrieval instructions, reasoning effort, embedding/query-planning models, and output behavior, and verify its configuration matches the declared inputs
- [ ] 7.3 Run initial extraction, chunking, vectorization, and indexing from a VNet-connected execution location, and verify every expected sample document reports successful ingestion
- [ ] 7.4 Add retrieval validation for keyword/vector/hybrid behavior as supported, expected citations, and insufficient-knowledge handling, and verify failed or incomplete ingestion keeps grounding readiness false
- [ ] 7.5 Add an incremental refresh test by changing one generic sample document, and verify the indexed knowledge source reflects the new version without duplicating stale content
- [ ] 7.6 Publish the shared Foundry IQ retrieval interface contract used by both agents, recording the retrieval endpoint and client SDK or API version, the managed-identity token audience and scope, the stable knowledge-base identifier, and the request and citation response shapes, and verify an undefined or unapproved element produces a named BLOCKED gate before task 9.2 starts

## 8. Implement the Foundry Prompt Agent

- [ ] 8.1 After task 7.6 and verified caller configuration from task 1.5, create a versioned prompt-agent definition using the approved model, Foundry IQ knowledge base, and Entra-authenticated APIM OpenAPI tool; verify its logical agent ID/version separately from the actual shared or dedicated Entra caller principal
- [ ] 8.2 Add instructions that require grounding and citations before relevant answers, governed APIM tool use for the selected operation, and explicit handling of insufficient knowledge or failed tools, and verify targeted prompt tests cover each behavior
- [ ] 8.3 Configure prompt-agent conversation persistence through Standard Agent Setup, and verify a conversation can be resumed using Foundry-managed Cosmos DB state after a new client session
- [ ] 8.4 Add prompt-agent telemetry and correlation metadata without recording sensitive prompt or document bodies by default, and verify agent traces appear in the agent Application Insights component
- [ ] 8.5 Add prompt-agent deployment and smoke-test automation, and verify grounding, citation, APIM tool invocation, memory continuity, and telemetry checks pass together

## 9. Implement the AKS-Hosted Agent

- [ ] 9.1 Create the independent code-based agent under a dedicated source directory with health endpoints and configuration for Foundry IQ, APIM, Cosmos DB, and telemetry, and verify local unit tests run without live Azure credentials
- [ ] 9.2 Implement Foundry IQ retrieval and citation handling against the published shared retrieval interface contract from task 7.6 without proxying the prompt agent or querying the Azure AI Search index directly, and verify grounding tests produce the expected source-backed behavior
- [ ] 9.3 Implement APIM-only tool invocation with managed authentication, explicit timeout/error handling, and correlation propagation, and verify mocked success, unauthorized, throttled, timeout, and backend-error tests pass
- [ ] 9.4 Implement application-owned Cosmos DB conversation persistence using the AKS workload identity and a namespace separate from Foundry-managed stores, and verify repository tests cover partitioning, resume, update, and isolation behavior
- [ ] 9.5 Instrument agent requests, Foundry IQ dependencies, APIM calls, Cosmos DB operations, exceptions, and latency with OpenTelemetry/Application Insights correlation, and verify no credential or full message body is emitted by default
- [ ] 9.6 Build and deploy the immutable agent image to the approved AKS cluster, and verify rollout completion, readiness/liveness probes, bounded resources, and invocation through the approved endpoint
- [ ] 9.7 Restart or replace the AKS pod during an active validation conversation, and verify the resumed conversation reloads state from Cosmos DB rather than pod-local storage

## 10. Add Shared End-to-End Validation

- [ ] 10.1 Create one reusable validation runner that targets either agent while applying the same grounding, citation, tool, memory, identity, connectivity, and telemetry assertions, and verify local contract tests cover runtime-specific adapters
- [ ] 10.2 Add management-plane checks for resource placement, public access, private endpoints, DNS associations, identities, RBAC, model approvals, AKS prerequisites, and deployed versions, and verify each check emits a structured readiness status
- [ ] 10.3 Add VNet-connected data-plane checks for Storage, Foundry IQ, prompt-agent invocation, AKS-agent invocation, APIM tools, and Cosmos DB continuity, and verify the runner cannot silently fall back to public endpoints
- [ ] 10.4 Add trace validation that reconstructs one transaction across the agent, Foundry IQ, APIM, tool backend, Cosmos DB, and Azure dependencies, and verify both APIM and agent Application Insights components contain their expected portions
- [ ] 10.5 Add negative tests for unavailable grounding, unauthorized tools, tool timeout, failed persistence, missing AKS prerequisites, unresolved private DNS, and absent telemetry, and verify each failure keeps overall readiness false
- [ ] 10.6 Generate redacted validation evidence for both agents with correlation IDs, status, timings, source identifiers, deployment versions, and failed gates, and verify the confidentiality scan finds no customer identifiers, credentials, tokens, or unnecessary content

## 11. Documentation, CI, and Release Readiness

- [ ] 11.1 Update Chapters 06-08 with the implemented knowledge-base, prompt-agent, and AKS flows, retaining Foundry-managed hosted-agent guidance as a separately labelled follow-on rather than deleting it or claiming AKS equivalence; verify current commands map to repository artifacts and follow-on examples are not initial acceptance evidence
- [ ] 11.2 Document the three lifecycle commands, explicit handoffs, owner-managed monitoring reuse, rollback boundaries, and stage-specific BLOCKED states; verify operators can prepare shared services without Foundry and onboard another project without rerunning account/shared provisioning
- [ ] 11.3 Document POC sharing limits, common permission for shared Foundry caller identities, and deferred business-unit/isolation/capacity/chargeback/retention design; record the third managed hosted-agent runtime as a separate follow-on requiring identity/network/memory/telemetry feasibility and reuse of the common contracts where supported, and verify its absence does not block or count as passed in initial acceptance
- [ ] 11.4 Add targeted CI jobs for Bicep builds, module contracts, agent unit tests, Kubernetes manifest validation, confidentiality scanning, and non-live validation contracts, and verify the pull-request workflow passes
- [ ] 11.5 Run the full approved live Phase 1 demonstration for both agents and record grounding citations, APIM tool results, memory continuity, AKS readiness, and correlated telemetry, and verify all mandatory gates pass before marking the implementation complete

## Dependency and Evidence Boundaries

Task order is not permission to bypass prerequisites. Tasks 1.1-1.3, 1.5-1.6 establish contracts;
task 1.5's live Foundry identity evidence follows account/project availability from section 6.
Offline policy/backend work can proceed with fixtures, but task 4.6 and prompt-tool activation
wait for that evidence. Tenant application provisioning is an operator prerequisite, not an
agent permission.

Section 2 can proceed without Foundry; complete applicable private DNS/monitoring-owner actions
before claiming those resources ready. Section 3 consumes the Storage readiness from section 2.
Tasks 4.1 and 4.6 need the approved cluster/private routing in 5.1 and a deployed backend; they do
not depend on the AKS agent's later Foundry IQ integration. Sections 4 and 5 may otherwise proceed
independently of Foundry.

Section 6 requires its shared-service/network prerequisites and approval, not a Foundry telemetry
or tool-ready flag that depends on resources it is about to create, then orders account -> project ->
connections/RBAC -> capability. Section 7 consumes these readiness outputs and approved models;
task 7.6 must be resolved before agent retrieval work in sections 8-9. Section 10 requires both
initial runtimes and repeats sender-specific monitoring checks. Task 11.5 depends on all initial
mandatory gates, including second-project non-interference, but never on the deferred third runtime.
Compilation, evaluated contract fixtures, and live evidence are distinct; unavailable mandatory
live checks remain BLOCKED, not satisfied by mocks or successful OpenSpec validation.
