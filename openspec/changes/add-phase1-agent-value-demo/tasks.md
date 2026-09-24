## 1. Confirm Phase 1 Inputs and Contracts

- [ ] 1.1 Record the approved AKS cluster resource ID, namespace, ingress pattern, workload-identity issuer, and container registry inputs in the deployment contract, and verify missing values produce a BLOCKED prerequisite result rather than a success-shaped default
- [ ] 1.2 Select and document one safe deterministic APIM-managed tool operation for acceptance testing, and verify its expected request, response, authorization, and failure contracts are reproducible
- [ ] 1.3 Record approved chat, embedding, and Foundry IQ query-planning model deployments and regional availability, and verify preflight fails closed when approval or capacity evidence is absent
- [ ] 1.4 Update the relevant legacy feature specs and Chapters 06-08 to link issue #83 and this OpenSpec change, and verify the documented Phase 1 scope distinguishes the prompt agent, AKS-hosted agent, and deferred Phase 2 architecture

## 2. Build the Pre-Approval Shared Platform

- [ ] 2.1 Add a parameterized Phase 1 environment composition entry point that deploys or reuses the shared Cosmos DB, Storage, and Azure AI Search resources, and verify Bicep compilation and resource-group what-if succeed
- [ ] 2.2 Add a workspace-based agent Application Insights component that remains separate from the APIM component and either reuses the supplied approved Log Analytics workspace or creates a dedicated Phase 1 workspace when none is supplied, and verify outputs identify both telemetry boundaries and that an unavailable or unapproved workspace produces a named BLOCKED gate instead of a component without workspace integration
- [ ] 2.3 Add or reuse bare private endpoints for Cosmos DB, Storage, Azure AI Search, and agent observability dependencies without violating the existing staged DNS-association contract, and verify what-if introduces no duplicate endpoints or DNS zones
- [ ] 2.4 Add the later DNS-association wiring for any new private endpoints, and verify each supplied full private-endpoint resource ID can be associated or independently skipped
- [ ] 2.5 Add baseline operational identities and least-privilege management/data-plane role assignments that do not depend on a Foundry project, and verify no developer, validation, or runtime identity receives broad Owner, Contributor, or unnecessary data-owner access
- [ ] 2.6 Add outputs and readiness states that distinguish existing, deployed, pending, blocked, and failed shared resources, and verify Foundry-dependent states remain BLOCKED while the pre-approval platform can still report its own readiness
- [ ] 2.7 Add module contract tests for shared-resource reuse, separate agent observability, private-endpoint flags, staged DNS inputs, and approval gates, and verify the targeted infrastructure tests pass

## 3. Prepare the Foundry IQ Sample Corpus

- [ ] 3.1 Create a small generic non-sensitive sample document corpus with stable source identifiers and expected factual answers, and verify the repository confidentiality scan passes
- [ ] 3.2 Add an idempotent managed-identity upload process for a dedicated Phase 1 Storage container, and verify repeated uploads produce the declared document set without embedding account keys
- [ ] 3.3 Define grounding test cases for answerable questions, unanswerable questions, expected source references, and minimum relevance behavior, and verify each expected answer maps to a committed generic source document
- [ ] 3.4 Add pre-approval Storage validation for private DNS, private reachability, identity-based list/read access, and sample-corpus completeness, and verify failures keep corpus readiness false

## 4. Prepare Governed APIM Tool Access

- [ ] 4.1 Add or adapt the selected deterministic tool backend and its API or MCP contract without introducing customer data, and verify it returns stable success and controlled failure responses
- [ ] 4.2 Configure the APIM backend, API or MCP surface, products/policies, and managed authentication for the selected tool, and verify the existing staged APIM integration remains independently deployable
- [ ] 4.3 Ensure agent runtime configuration exposes only the APIM endpoint for the protected tool, and verify a repository test fails if the protected backend endpoint is configured directly
- [ ] 4.4 Add authorization, throttling, timeout, error mapping, and correlation propagation policies, and verify authorized calls succeed while unauthorized and backend-failure scenarios are rejected without false success
- [ ] 4.5 Extend APIM validation evidence for the selected tool operation and correlation identifier, and verify gateway telemetry remains in the APIM-dedicated Application Insights component

## 5. Prepare the AKS Delivery Foundation

- [ ] 5.1 Add prerequisite validation for the approved AKS cluster, namespace, OIDC/workload-identity configuration, registry access, network routes, private DNS, and ingress pattern, and verify each missing prerequisite produces a named BLOCKED gate
- [ ] 5.2 Add an AKS workload identity and federated service-account binding scoped to the agent namespace, and verify token acquisition works without Kubernetes secrets containing Azure credentials
- [ ] 5.3 Add least-privilege AKS-agent data-plane role assignments for its application-owned Cosmos DB scope, Foundry IQ access, APIM invocation, and telemetry ingestion, and verify effective permissions do not include Foundry-managed Cosmos structures
- [ ] 5.4 Add the container build and registry publication pipeline for the code-based agent with immutable image versioning, and verify the built image can be pulled by the approved cluster identity
- [ ] 5.5 Add parameterized Kubernetes deployment, service, configuration, health probes, resource requests/limits, disruption behavior, and network policy artifacts, and verify server-side manifest validation succeeds against the target cluster version

## 6. Activate Foundry Standard Agent Setup

- [ ] 6.1 Extend Foundry preflight to require the approved project endpoint, project identity, model approvals, private connectivity, and current provider/API support before activation, and verify it fails closed when any gate is unresolved
- [ ] 6.2 Reuse or extend the existing project connections for Cosmos DB, Storage, and Azure AI Search with managed authentication, and verify each connection references the resolved shared Phase 1 resource ID
- [ ] 6.3 Apply the minimum project-identity RBAC required for Foundry-managed Cosmos DB, Storage, and Azure AI Search operations, and verify assignments are present before capability-host activation
- [ ] 6.4 Activate the Agents capability host only after project connections and RBAC are ready, and verify Foundry can provision its managed persistence structures without account keys
- [ ] 6.5 Add validation that Foundry-managed Cosmos DB structures are absent before activation and provider-created afterward, and verify the deployment never manually creates containers using Foundry-managed names

## 7. Create and Validate Foundry IQ

- [ ] 7.1 Add idempotent automation for the indexed Blob Storage knowledge source using the approved identity and sample container, and verify the resulting object references the intended Storage resource and container
- [ ] 7.2 Add idempotent automation for the knowledge base with approved retrieval instructions, reasoning effort, embedding/query-planning models, and output behavior, and verify its configuration matches the declared inputs
- [ ] 7.3 Run initial extraction, chunking, vectorization, and indexing from a VNet-connected execution location, and verify every expected sample document reports successful ingestion
- [ ] 7.4 Add retrieval validation for keyword/vector/hybrid behavior as supported, expected citations, and insufficient-knowledge handling, and verify failed or incomplete ingestion keeps grounding readiness false
- [ ] 7.5 Add an incremental refresh test by changing one generic sample document, and verify the indexed knowledge source reflects the new version without duplicating stale content
- [ ] 7.6 Publish the shared Foundry IQ retrieval interface contract used by both agents, recording the retrieval endpoint and client SDK or API version, the managed-identity token audience and scope, the stable knowledge-base identifier, and the request and citation response shapes, and verify an undefined or unapproved element produces a named BLOCKED gate before task 9.2 starts

## 8. Implement the Foundry Prompt Agent

- [ ] 8.1 Create a versioned prompt-agent definition that uses the approved model, Foundry IQ knowledge base, and APIM-managed tool connection, and verify deployment creates a distinct prompt-agent identity and version
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

- [ ] 11.1 Update Chapters 06-08 with the implemented Foundry IQ knowledge-base terminology, prompt-agent flow, and AKS-hosted-agent flow, and verify every documented command and path maps to a repository artifact
- [ ] 11.2 Document the pre-approval and post-approval deployment sequence, rollback boundaries, and BLOCKED readiness semantics, and verify operators can complete the shared-resource stage without Foundry
- [ ] 11.3 Document that Phase 1 resources are shared but not a permanent global architecture, including the Phase 2 isolation, capacity, chargeback, retention, and lifecycle decisions, and verify the limitation is visible in both architecture and operator guidance
- [ ] 11.4 Add targeted CI jobs for Bicep builds, module contracts, agent unit tests, Kubernetes manifest validation, confidentiality scanning, and non-live validation contracts, and verify the pull-request workflow passes
- [ ] 11.5 Run the full approved live Phase 1 demonstration for both agents and record grounding citations, APIM tool results, memory continuity, AKS readiness, and correlated telemetry, and verify all mandatory gates pass before marking the implementation complete
