## Purpose

Defines a reusable Foundry IQ knowledge layer that grounds both Phase 1 agents in approved,
non-sensitive sample content with verifiable citations.

## ADDED Requirements

### Requirement: Foundry IQ knowledge base
After Foundry approval, the solution SHALL create a Foundry IQ knowledge base in Azure AI Search
with at least one indexed knowledge source backed by the Phase 1 Storage sample corpus.

#### Scenario: Create indexed knowledge source
- **WHEN** the approved Foundry project, Search service, Storage connection, model deployment, and required identities are available
- **THEN** the solution creates the knowledge source and knowledge base using managed authentication

#### Scenario: Keep Foundry-dependent creation gated
- **WHEN** the Foundry project or required model approval is unavailable
- **THEN** the sample corpus remains prepared but no success result is reported for the Foundry IQ knowledge base

### Requirement: Searchable ingestion pipeline
The Foundry IQ ingestion process SHALL extract, chunk, vectorize, index, and refresh the approved
sample documents using a supported configuration.

#### Scenario: Complete initial ingestion
- **WHEN** ingestion runs against the prepared sample corpus
- **THEN** every expected sample document is represented in the indexed knowledge source and reports a successful ingestion state

#### Scenario: Detect incomplete ingestion
- **WHEN** an expected document cannot be extracted, vectorized, or indexed
- **THEN** validation reports the document and failed stage and keeps grounding readiness false

### Requirement: Grounded retrieval with citations
The knowledge base SHALL return relevant content and source references for the approved grounding
test questions.

#### Scenario: Retrieve an expected answer
- **WHEN** a test question is answerable from the sample corpus
- **THEN** retrieval returns content from the expected source document with a usable source reference

#### Scenario: Avoid unsupported claims
- **WHEN** a test question is not answerable from the indexed knowledge sources
- **THEN** the consuming agent indicates that the available knowledge is insufficient rather than presenting an unsupported grounded answer

### Requirement: Shared knowledge contract for both agents
The prompt agent and AKS-hosted agent SHALL use the same approved knowledge base and grounding
test corpus for the Phase 1 comparison.

#### Scenario: Compare grounding behavior
- **WHEN** the same grounding test is sent to both agents
- **THEN** both agents invoke the approved knowledge base and return source-backed responses that satisfy the same expected-answer criteria
