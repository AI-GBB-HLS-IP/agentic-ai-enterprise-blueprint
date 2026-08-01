# Chapter 00 — Microsoft Secure Internet of Agents: Platform Overview

## Introduction

The **Microsoft Secure Internet of Agents** is an enterprise-scale architecture that transforms how organizations build, deploy, discover, and govern AI agents. Rather than each team independently building and managing their own AI integrations, this platform provides a centralized, secure, and governed environment where agents, tools, skills, and knowledge assets are first-class citizens.

This overview chapter provides a deep dive into the architecture, explains each layer, and establishes the design principles that guide every subsequent lab chapter.

---

## The Problem We're Solving

As enterprises adopt AI at scale, several challenges emerge:

1. **Agent Sprawl** — Teams independently build agents with inconsistent security, authentication, and quality standards
2. **Tool Duplication** — The same API integrations are reimplemented across teams with no reuse
3. **Authentication Complexity** — Each agent needs its own authentication setup, key management, and credential rotation
4. **No Governance** — No visibility into what agents exist, what data they access, or what models they use
5. **Cost Opacity** — No centralized tracking of token consumption, model usage, or cost attribution
6. **Security Gaps** — No consistent content safety, prompt injection protection, or threat detection
7. **Discovery Barriers** — Developers can't find existing agents or tools, leading to redundant work
8. **Fragmented Intelligence** — Data locked in silos (Microsoft 365, data warehouses, knowledge bases, web) cannot be accessed uniformly by agents

---

## Platform Value: Why Microsoft's Internet of Agents

The Internet of Agents platform solves the problems above not through process alone, but through **architecture that makes the right thing the easy thing**. The value is delivered across three dimensions: **data intelligence** (IQ layers), **security and observability** (AI Gateway + Defender + Foundry), and **universal discoverability** (agents, tools, and skills available instantly).

---

### Dimension 1: The IQ Layer — Your Data Becomes Agent Intelligence

Microsoft's approach is built on **IQ layers** — purpose-built intelligence services that give agents governed, native access to enterprise data without requiring developers to build custom RAG pipelines, manage embeddings, or wire up retrieval logic:

### The IQ Family

| IQ Layer | Data Domain | What It Unlocks |
|----------|-------------|-----------------|
| **Work IQ** | Microsoft 365 (emails, calendar, Teams chats, OneDrive, SharePoint) | Agents grounded in the user's organizational context — who they work with, what they're working on, meeting notes, email threads, and shared documents |
| **Foundry IQ** | Enterprise knowledge bases (blob storage, databases, SharePoint libraries) | RAG-powered agents with hybrid search across organizational knowledge indexes, with automatic chunking, embedding, and retrieval |
| **Fabric IQ** | Data lakes, warehouses, semantic models (Lakehouse, Delta Tables, Power BI) | Agents that can query terabytes of structured enterprise data using natural language, powered by Fabric's unified analytics platform |
| **Web IQ** | Public internet, web pages, real-time information | Agents grounded in current world events, documentation, public data, and real-time information not available in internal systems |

### How IQ Powers Agents

The IQ ecosystem is what makes Microsoft's agent platform fundamentally different:

1. **Grounded Intelligence** — Every agent response can be grounded in real enterprise data. A procurement agent doesn't hallucinate supplier information — it queries Fabric IQ for actual contract data, checks Work IQ for recent email negotiations, and references Foundry IQ for procurement policies.

2. **Unified Data Access Without Complexity** — Developers don't need to build custom RAG pipelines for each data source. The IQ layers provide standardized, secure, governed access. An agent simply declares "I need Work IQ" and gains access to organizational knowledge through a consistent SDK interface.

3. **Security Boundary Preservation** — Each IQ layer enforces its own security model. Work IQ uses On-Behalf-Of (OBO) authentication to ensure agents only see data the requesting user has permission to access. Fabric IQ respects row-level security on semantic models. Foundry IQ applies document-level ACLs.

4. **The Compound Intelligence Effect** — When agents combine multiple IQs, the result is exponentially more powerful than any single data source:
   - A customer success agent: Work IQ (recent support emails) + Fabric IQ (usage metrics from data warehouse) + Foundry IQ (product documentation) = deeply contextual, data-grounded customer interactions
   - A financial planning agent: Fabric IQ (financial data models) + Work IQ (executive communications) + Web IQ (market conditions) = informed strategic recommendations

5. **Data as a Competitive Moat** — Your organization's proprietary data, accessed through the IQ ecosystem, becomes the differentiator. The models are commoditized; your data is not. This platform unlocks that data safely.

---

### Dimension 2: AI Gateway + Defender + Foundry — Security and Observability Without Friction

Security in this platform is not a review gate that slows teams down — it's **baked into the architecture at the network, gateway, and runtime layers**. Developers get security for free. Security teams get visibility without chasing individual teams.

| Component | What It Does | Why It Matters |
|-----------|-------------|----------------|
| **AI Gateway (APIM)** | Single chokepoint for all model and tool access. Enforces rate limiting, token quotas, content filtering, JWT validation, and full audit logging. | Developers don't implement security — they inherit it. Every call is governed by policy regardless of who wrote the agent. |
| **Microsoft Agent 365** | Enterprise control plane for agents — centralized agent registry, lifecycle governance, and unified observe/govern/secure experience across all agent types (Foundry, third-party, partner). | Admins see every agent in one registry. Lifecycle management, access control, and compliance are centralized. Security and business leaders get role-specific oversight. |
| **Microsoft Defender for AI** | Continuous agent inventory, risk scoring, threat detection, and attack path analysis across all deployed agents. | SOC teams see AI-specific threats alongside traditional security events. No separate tooling, no agent-by-agent setup. |
| **Foundry Evaluations** | Automated quality and safety scoring (groundedness, relevance, coherence, safety) integrated into CI/CD pipelines. | Bad agents are blocked from production automatically — no manual review for every deployment. Quality is enforced by the pipeline, not by humans. |
| **Content Safety + Prompt Shields** | Every input and output scanned for injection attacks, harmful content, jailbreaks, and data leakage — applied at the gateway level. | Developers cannot disable it. Even if an agent has a vulnerability, the platform catches the exploit before damage occurs. |
| **Azure Policy** | Infrastructure guardrails that prevent non-compliant deployments (no public endpoints, no disabled logging, no unvetted models) before they exist. | Governance-as-code, not governance-as-checklist. Non-compliant resources are denied at creation time. |
| **Application Insights + OpenTelemetry** | Distributed tracing, metrics, and logs for every agent interaction — correlated across the full call chain (user → APIM → model → tool → response). | Observability is non-optional. Every agent is monitored from day one. Incidents are detected by the platform, not reported by users. |

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SECURITY & OBSERVABILITY STACK                    │
│                                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────┐ │
│  │  Azure       │  │  AI Gateway  │  │  Foundry     │  │Defender │ │
│  │  Policy      │  │  (APIM)      │  │  Evaluations │  │ for AI  │ │
│  │             │  │              │  │              │  │         │ │
│  │  Blocks bad  │  │  Enforces    │  │  Blocks bad  │  │ Detects │ │
│  │  infra at    │  │  security on │  │  agents at   │  │ threats │ │
│  │  deploy time │  │  every call  │  │  CI/CD time  │  │ at      │ │
│  │              │  │              │  │              │  │ runtime │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └────┬────┘ │
│         │                 │                 │               │      │
│         ▼                 ▼                 ▼               ▼      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │         Microsoft Agent 365 — Unified Control Plane            │ │
│  │  Centralized agent registry, lifecycle governance, observe/    │ │
│  │  govern/secure across all agents (Foundry, third-party, M365) │ │
│  └────────────────────────────────────────────────────────────────┘ │
│         │                 │                 │               │      │
│         ▼                 ▼                 ▼               ▼      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │           Application Insights + Log Analytics                 │ │
│  │     Full telemetry, KQL queries, dashboards, alerts            │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘

Result: Security teams set policy ONCE → applies to ALL agents FOREVER
        Agent 365 provides unified observe/govern/secure for all agents
        No per-team audits. No per-agent reviews. No manual checklists.
```

---

### Dimension 3: Universal Discoverability — No More Reinventing the Wheel

The platform makes every agent, tool, skill, and knowledge asset **discoverable and consumable** without tickets, meetings, or manual onboarding:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DISCOVERABILITY STACK                            │
│                                                                     │
│  ┌─────────────────┐   ┌──────────────────┐   ┌────────────────┐  │
│  │  API Center      │   │  A2A Agent Cards  │   │  React          │  │
│  │  (Tool Registry) │   │  (Agent Registry) │   │  Discovery UI   │  │
│  │                  │   │                   │   │                 │  │
│  │  • MCP tools     │   │  • Agent          │   │  • Browse all   │  │
│  │  • REST APIs     │   │    capabilities   │   │    agents       │  │
│  │  • Skills        │   │  • Input/output   │   │  • Search by    │  │
│  │  • Usage stats   │   │    schemas        │   │    capability   │  │
│  │  • SLA/quality   │   │  • Trust level    │   │  • One-click    │  │
│  │  • Examples      │   │  • Owner/team     │   │    integrate    │  │
│  └─────────────────┘   └──────────────────┘   └────────────────┘  │
│                                                                     │
│  Developer's experience:                                            │
│  "I need a tool that looks up customer data"                        │
│  → Search API Center → Find get-customer-data MCP tool              │
│  → Already governed by APIM → Use immediately, no setup needed      │
│                                                                     │
│  "I need an agent that can summarize financial reports"              │
│  → Browse A2A catalog → Find finance-summarizer agent               │
│  → Delegate via A2A protocol → Governed, logged, rate-limited       │
└─────────────────────────────────────────────────────────────────────┘
```

**Why discoverability matters at enterprise scale:**

| Without Discoverability | With This Platform |
|------------------------|-------------------|
| Team A builds "customer lookup" tool, unaware Team B already built one | One registered tool in API Center, used by 12 teams |
| 60% of developer time spent rediscovering capabilities that already exist | Browse catalog → integrate in minutes |
| Custom auth for each integration; each team manages their own API keys | APIM handles all auth; developers use managed identity |
| No way to know what agents exist across the organization | Full catalog with capabilities, SLAs, usage metrics, and examples |
| Agents can't find other agents — manual wiring required | A2A protocol enables runtime discovery and delegation |

**The platform principle:** Publish once → discoverable everywhere → governed automatically.

---

## The Governed Flow: How Standards Meet Developer Velocity

The second dimension of this platform's value is **how it organizes people**. The Internet of Agents separates responsibilities into clear roles with guardrails that make everyone's job easier — not harder.

### Why Separation of Duties Matters

Without clear role boundaries:
- Developers create infrastructure → security gaps, cost sprawl, inconsistency
- IT teams review every agent manually → bottleneck, slow velocity, frustrated developers  
- Nobody owns governance → policies exist on paper but not in practice
- AI CoE doesn't exist or is overwhelmed → no quality standards, no evaluation, no oversight

The Internet of Agents solves this by making **each role self-sufficient within their boundary** while making it **impossible to cross boundaries** — even accidentally:

### The Three Roles and Their Day-in-Life

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│  ┌─────────────────────────┐                                          │
│  │  IT / PLATFORM            │  "We build the platform once.           │
│  │  ENGINEERING              │   Everyone benefits forever."            │
│  │                           │                                          │
│  │  What they do:            │  Day-in-Life:                            │
│  │  • Deploy VNets & NSGs    │  ☐ Check platform health dashboard      │
│  │  • Configure APIM Gateway │  ☐ Respond to capacity alerts           │
│  │  • Set Azure Policy       │  ☐ Update policies as new threats emerge│
│  │  • Deploy Defender & Logs │  ☐ Patch and upgrade infra              │
│  │  • Manage DNS & endpoints │  ☐ Review Agent 365 registry health     │
│  │  • Manage Agent 365 sync  │  ☐ Review cost anomalies                │
│  │                           │                                          │
│  │  What they DON'T do:      │  What the platform gives them:          │
│  │  ✗ Write agent code       │  • Azure Policy does enforcement        │
│  │  ✗ Review agent PRs       │  • Defender does threat detection        │
│  │  ✗ Deploy agents          │  • APIM does rate limiting               │
│  │  ✗ Manage models          │  • Agent 365 unified observe/govern      │
│  │                           │  • No per-team infrastructure work      │
│  └──────────┬────────────────┘                                          │
│             │                                                           │
│             │ Provides: secure, governed infrastructure                  │
│             ▼                                                           │
│  ┌─────────────────────────┐                                          │
│  │  AI CENTER OF             │  "We ensure quality and safety.          │
│  │  EXCELLENCE (AI CoE)      │   Developers come to us for projects."   │
│  │                           │                                          │
│  │  What they do:            │  Day-in-Life:                            │
│  │  • Approve project reqs   │  ☐ Review incoming project requests     │
│  │  • Run Foundry blueprints │  ☐ Provision new projects (run Bicep)   │
│  │  • Manage tool registry   │  ☐ Approve tools for the catalog        │
│  │  • Review PRs (CODEOWNERS)│  ☐ Review CI/CD gate results            │
│  │  • Deploy to production   │  ☐ Investigate failed evaluations       │
│  │  • Set eval thresholds    │  ☐ Manage Agent 365 lifecycle policies  │
│  │                           │                                          │
│  │  What they DON'T do:      │  What the platform gives them:          │
│  │  ✗ Modify network/VNet    │  • CI/CD gates auto-verify quality      │
│  │  ✗ Change Azure Policy    │  • Blueprint makes provisioning 5 min   │
│  │  ✗ Disable logging        │  • Only review results, not code        │
│  │  ✗ Write agent code       │  • Tool registry is self-service submit │
│  └──────────┬────────────────┘                                          │
│             │                                                           │
│             │ Provides: governed projects, approved tools, oversight     │
│             ▼                                                           │
│  ┌─────────────────────────┐                                          │
│  │  DEVELOPERS               │  "We build great agents.                 │
│  │                           │   The platform handles the rest."         │
│  │                           │                                          │
│  │  What they do:            │  Day-in-Life:                            │
│  │  • Write agent code       │  ☐ Browse tool catalog for capabilities │
│  │  • Use approved tools     │  ☐ Code against APIM endpoints          │
│  │  • Test locally           │  ☐ Test locally with guardrails active  │
│  │  • Submit PRs             │  ☐ Push PR, watch CI/CD gates pass      │
│  │                           │  ☐ Ship to production same day          │
│  │  What they DON'T do:      │                                          │
│  │  ✗ Create infrastructure  │  What the platform gives them:          │
│  │  ✗ Access models directly │  • No infra tickets or waiting          │
│  │  ✗ Bypass guardrails      │  • No security reviews to pass          │
│  │  ✗ Deploy to production   │  • No key management                    │
│  │  ✗ Disable content safety │  • No monitoring setup                  │
│  │                           │  • Self-service tool discovery           │
│  └───────────────────────────┘                                          │
└───────────────────────────────────────────────────────────────────────┘
```

### How the Platform Makes Each Role's Job Easier

| Role | Without This Platform | With This Platform |
|------|----------------------|-------------------|
| **IT / Platform Eng** | Chase every team for compliance. Manually audit agents. Write custom monitoring for each deployment. Respond to incidents with no context. | Set policy once → Azure Policy enforces everywhere. Deploy Defender once → all agents monitored automatically. Agent 365 provides unified registry and control plane. No per-team work ever. |
| **AI CoE** | Review security for every agent manually. No standard for what "good" looks like. Bottleneck on every deployment. Overwhelmed by requests. | Run a Bicep blueprint → project is secure by construction. CI/CD gates auto-verify quality. Agent 365 lifecycle governance ensures compliance. Only review results, not implementation details. Same-day turnaround. |
| **Developers** | File tickets for infrastructure. Wait days for security review. Set up monitoring. Manage API keys. Build custom auth flows. Reinvent tools that already exist. | Receive a project with everything pre-configured. Browse the tool catalog. Code, test, push. Ship the same day. Focus on business logic, not plumbing. |

### The Standards Flow — Who Creates, Who Follows

```
  IT / Platform Eng                AI CoE                    Developers
  ─────────────────               ──────                    ──────────
        │                            │                           │
  1. Deploy platform            2. Define standards              │
     (one-time setup)              • Approved models             │
     • VNet + NSGs                 • Tool registry               │
     • APIM AI Gateway             • Eval thresholds             │
     • Azure Policy                • Blueprint params            │
     • Defender + Logs             │                             │
        │                          │                             │
        │                          │                             │
   Azure Policy ══════════════════▶│ (enforced automatically)    │
   enforces infra                  │                             │
   standards on                    │                             │
   everything                      │                             │
        │                          │                             │
        │                    3. Developer submits ◀──────────────│
        │                       project request                  │
        │                          │                             │
        │                    4. AI CoE runs blueprint            │
        │                       (5 min, fully automated)         │
        │                          │                             │
        │                          ├─────── hardened project ───▶│
        │                          │        + onboarding package │
        │                          │                             │
        │                          │                       5. Developer builds
        │                          │                          agent (uses APIM
        │                          │                          endpoints only)
        │                          │                             │
        │                          │                       6. Browses tool
        │                          │                          catalog, integrates
        │                          │                          existing tools
        │                          │                             │
        │                          │◀──── 7. Submits PR ────────│
        │                          │                             │
        │                    8. CI/CD gates run                   │
        │                       (6 automated checks)             │
        │                          │                             │
        │                    9. AI CoE reviews result             │
        │                       (not the code — the gates)       │
        │                          │                             │
        │                   10. Deploys to production             │
        │                          │                             │
   Defender monitors ◀─────────────┼─────────────────────────────┤
   for threats                     │                      Developer sees
        │                          │                      own metrics in
        │                     AI CoE sees                  App Insights
        │                     quality dashboard                  │
        │                          │                             │
```

### The Key Insight

The platform doesn't add gates — it **removes work** from every role:

- **IT** no longer chases compliance — Azure Policy enforces it at resource creation time
- **AI CoE** no longer manually audits security — CI/CD gates verify it automatically in every PR
- **Developers** no longer wait for infrastructure or security approval — they get a pre-built, pre-secured environment instantly

**Everyone does less busywork. Everyone ships faster. And the organization stays secure.**

---

## Developer Self-Service and Acceleration

### The Discovery Problem in Enterprise AI

In a typical enterprise, teams reinvent the wheel daily:
- Team A builds a "customer lookup" MCP tool, unaware Team B already built one
- Team C exposes their agent via REST but uses custom auth that nobody can integrate with
- Team D has a fantastic knowledge base but no way for other teams' agents to access it

### How This Platform Accelerates Development

This architecture provides a **developer self-service model** that eliminates these friction points:

#### 1. Enterprise MCP Discovery via API Center

Azure API Center serves as the centralized registry where every MCP server, skill, and API is cataloged with rich metadata. Developers can:
- Browse available MCP tools through the React Discovery UI or Azure Portal
- Search by capability ("I need a tool that can look up customer contracts")
- See usage metrics, SLAs, and examples for each tool
- Instantly consume any registered tool through the governed AI Gateway

#### 2. Agent Discovery via A2A Protocol

The Agent-to-Agent (A2A) protocol enables agents to discover and delegate to other agents:
- Every agent publishes an **Agent Card** describing its capabilities
- Agent Cards are registered in the enterprise catalog
- Agents can dynamically find and invoke other agents at runtime
- The AI Gateway (APIM) governs all A2A traffic with authentication, rate limiting, and monitoring

#### 3. Skill Composition Without Infrastructure Work

Developers compose complex agent behaviors by assembling existing building blocks:
- Connect to pre-built MCP tools (no API key management — APIM handles it)
- Delegate to specialized agents (the A2A mesh handles routing)
- Ground responses in enterprise knowledge (IQ layers handle retrieval)
- All through a consistent SDK experience (Microsoft Agent Framework)

#### 4. From Weeks to Hours

What used to take weeks now takes hours:

| Traditional Approach | Internet of Agents Approach |
|---------------------|----------------------------|
| Build custom auth for each API | One managed identity, APIM handles the rest |
| Implement RAG pipeline from scratch | Declare an IQ dependency, get grounded retrieval |
| Deploy and manage infrastructure | Deploy to Foundry as hosted agent |
| Build monitoring from scratch | OpenTelemetry + Application Insights built-in |
| Hope other teams find your agent | Publish to catalog, auto-discoverable via A2A |

---

## Centralized Monitoring, Security & Governance

### Why Centralization Matters

Distributed monitoring creates blind spots. If each team monitors their own agents independently, nobody has a holistic view of:
- Total token consumption across the organization
- Which agents are experiencing errors or quality degradation
- Whether prompt injection attacks are targeting specific services
- Compliance violations or data exfiltration attempts

### The Platform's Governance Architecture

Every request flows through the AI Gateway (APIM), creating a **single pane of glass** for:

- **Token Economics** — Track consumption per team, per agent, per application. Set quotas, enforce limits, provide cost attribution dashboards.
- **Quality Monitoring** — Foundry Evaluations automatically score agent outputs for groundedness, relevance, coherence, and safety.
- **Security Monitoring** — Microsoft Defender for AI provides agent inventory, risk assessment, and active threat detection.
- **Microsoft Agent 365** — The enterprise control plane that provides a centralized agent registry, lifecycle governance (Govern), real-time visibility into agent adoption and health (Observe), and end-to-end protection via Entra + Purview + Defender (Secure). All agents — Foundry-built, third-party, and partner — are managed through a single admin experience.
- **Compliance Audit Trail** — Every interaction is logged with correlation IDs, enabling forensic analysis and regulatory compliance.
- **Policy Enforcement** — Azure Policy ensures all agents meet organizational standards before deployment.

---

## Agent Security: Attack Surfaces and Defenses

### The New Threat Landscape for AI Agents

AI agents introduce attack surfaces that don't exist in traditional applications. Understanding these threats is critical for enterprise adoption:

#### Attack Surface 1: Prompt Injection

**What it is:** Attackers embed malicious instructions within data that an agent processes (emails, documents, web pages), causing the agent to perform unintended actions.

**Categories:**
- **Direct Prompt Injection (Jailbreaks):** Users attempt to override system instructions to make the agent produce harmful content or bypass restrictions
- **Indirect Prompt Injection:** Malicious content hidden in external data sources (e.g., a carefully crafted email that instructs the agent to forward all emails to an attacker)

**How we defend:**
- **Prompt Shields** (Azure AI Content Safety) — Scans both user prompts and document content for injection attempts in real-time. Operates at the AI Gateway level, protecting all agents uniformly.
- **Task Adherence API** — Detects when an agent's tool use becomes misaligned, unintended, or premature in the context of a user interaction. Catches agents that have been manipulated into performing actions outside their intended scope.
- **System Message Hardening** — Best practices for system prompts that are resilient to override attempts.

#### Attack Surface 2: Data Exfiltration

**What it is:** Agents with access to sensitive data (via IQ layers or MCP tools) could be manipulated into leaking information through their responses, tool calls, or A2A delegations.

**How we defend:**
- **Groundedness Detection** — Verifies that agent responses are grounded in provided source material, preventing the agent from "inventing" responses that actually leak training data or accessed documents.
- **Output Filtering** — Content Safety applies to completions, catching PII or sensitive data in responses.
- **Tool Call Auditing** — Every MCP tool invocation is logged with full request/response, enabling detection of anomalous data access patterns.
- **Network Isolation** — VNet injection and private endpoints ensure agents cannot exfiltrate data to external endpoints.

#### Attack Surface 3: Tool Poisoning

**What it is:** An attacker compromises an MCP tool's description or response to manipulate agent behavior — for example, modifying a tool's schema to cause the agent to pass sensitive data to it.

**How we defend:**
- **Centralized Tool Registry** — All MCP tools are registered in API Center with verified schemas. Agents can only invoke tools through the governed gateway.
- **Schema Validation** — APIM policies validate tool call parameters against registered schemas before forwarding.
- **Publisher Verification** — Tools undergo review before being published to the enterprise catalog.

#### Attack Surface 4: Agent Impersonation

**What it is:** A malicious agent registers itself in the A2A mesh, impersonating a trusted agent to intercept delegations or return manipulated results.

**How we defend:**
- **Mutual TLS and JWT Validation** — All A2A communication through APIM requires verified agent identity.
- **Agent Card Signing** — Agent Cards are cryptographically signed and verified before registration.
- **RBAC on Agent Invocation** — Not all agents can call all other agents — explicit allow-lists govern delegation paths.

#### Attack Surface 5: Model Manipulation

**What it is:** Exploiting model vulnerabilities to extract system prompts, reveal training data, or produce harmful outputs.

**How we defend:**
- **Protected Material Detection** — Scans AI-generated text for known copyrighted content.
- **Custom Categories** — Define organization-specific content categories that should be blocked.
- **Model Router Policies** — Route sensitive requests to models with stronger safety training.

### Red Teaming: Proactive Defense

Red teaming is a best practice in responsible development of AI systems. It involves systematic adversarial testing to discover vulnerabilities before attackers do.

#### Red Teaming Methodology for Agent Systems

1. **Assemble Diverse Teams** — Include security experts, domain specialists, ethicists, and regular users. Different perspectives uncover different vulnerabilities.

2. **Open-Ended Exploration** — Start without a fixed list. Let red teamers creatively probe the system to discover unexpected failure modes across:
   - The LLM base model (via API)
   - The agent application (via UI)
   - The tool chain (via crafted inputs)
   - The A2A mesh (via agent impersonation)

3. **Guided Testing** — Use findings from open-ended exploration to create targeted test plans:
   - Prompt injection variants (direct, indirect, multi-turn)
   - Tool abuse scenarios (excessive calls, privilege escalation)
   - Data exfiltration attempts (via responses, tool calls, delegations)
   - Chain-of-thought manipulation (misleading intermediate reasoning)

4. **Iterative Rounds** — Red teaming is not a one-time event:
   - Round 1: Discover attack surface and catalog vulnerabilities
   - Round 2: Validate mitigations, discover bypasses
   - Round 3: Test with production-like data and configurations
   - Ongoing: Automated red teaming in CI/CD pipelines using Foundry Evaluations

5. **Record and Report** — Maintain detailed records of:
   - Exact prompts that triggered failures
   - System responses and their severity
   - Recommended mitigations and their effectiveness
   - Trends over time (are new rounds finding fewer issues?)

---

## Microsoft Defender for AI: Enterprise-Grade Protection

Microsoft Defender extends its security capabilities specifically for AI workloads, and integrates with **Microsoft Agent 365** — the unified control plane for observing, governing, and securing all agents in production:

### Microsoft Agent 365 — The Control Plane for Agents

[Microsoft Agent 365](https://learn.microsoft.com/en-us/microsoft-agent-365/overview) provides the ability to **observe**, **govern**, and **secure** the growing number of agents within organizations:

| Pillar | What It Does |
|--------|-------------|
| **Observe** | Centralized agent registry with real-time visibility into agent adoption, activity, and health. Role-specific dashboards for admins, security, and business leaders. |
| **Govern** | Lifecycle management, access control, and compliance through the Agent 365 registry in M365 admin center, Microsoft Entra, and Microsoft Purview. |
| **Secure** | End-to-end protection via Microsoft Entra (identity and risk-based access control), Microsoft Purview (data security, DLP, risk safeguards), and Microsoft Defender (threat detection and real-time runtime protection). |

### How Agent 365 Integrates with This Platform

- **Agent Registry Sync** — All agents deployed through the Secure Agent Factory (Foundry Prompt/Hosted agents, Functions agents, Custom Engine agents) are synced to the Agent 365 registry for unified visibility
- **Governance Alignment** — Agent 365 lifecycle policies complement Azure Policy and API Center governance, ensuring both infrastructure and agent-level controls are enforced
- **Security Telemetry** — Defender for AI feeds threat signals to Agent 365 for centralized risk dashboards visible to security leaders
- **Third-Party Agent Governance** — Partner and external agents registered through Agent 365 are subject to the same observe/govern/secure controls as internal agents

### Defender for AI Capabilities

| Feature | What It Does |
|---------|-------------|
| **AI Agent Inventory** | Automatically discovers all AI agents across your Azure subscriptions, mapping their dependencies, tools, and data sources |
| **Risk Assessment** | Evaluates each agent's risk profile based on data access, tool permissions, network exposure, and model capabilities |
| **Threat Detection** | Active monitoring for prompt injection attempts, data exfiltration, anomalous agent behavior, and credential abuse |
| **Security Recommendations** | Actionable guidance for hardening agent configurations, applying least-privilege, and closing security gaps |
| **Incident Response** | Integration with Microsoft Sentinel for SOC workflows — security analysts can investigate AI-specific incidents |
| **Attack Path Analysis** | Visualizes how an attacker could move through the agent mesh, identifying critical chokepoints |

### Integration with This Platform

Defender for AI is not an afterthought — it's woven into the architecture:
- The AI Gateway (APIM) feeds all telemetry to Defender for analysis
- Agent deployments in Foundry are automatically inventoried
- Tool registrations in API Center are correlated with access patterns
- Anomalous A2A traffic is flagged and can trigger automated containment

---

## Enterprise Governance: The Balance Between Security and Innovation

### The Lockdown Paradox

Enterprises face a fundamental tension:
- **Too restrictive:** Developers route around policies, use shadow AI, and lose productivity. The organization falls behind competitors who move faster.
- **Too permissive:** Data leaks, compliance violations, cost explosions, and security incidents erode trust and create regulatory exposure.

### Finding the Right Balance Through Threat Modeling

The key to resolving this tension is **threat modeling** — a structured approach to understanding what needs protecting and what level of risk is acceptable:

#### Step 1: Classify Agent Workloads

Not all agents need the same security posture:

| Classification | Example | Controls |
|---------------|---------|----------|
| **Tier 1 — Public-Facing** | Customer support agents | Maximum safety filters, human-in-the-loop for sensitive actions, restricted tool access, no Work IQ |
| **Tier 2 — Internal Productivity** | Meeting summarization, code assistance | Standard content safety, Work IQ with OBO auth, MCP tools for internal systems |
| **Tier 3 — Specialized/Regulated** | Financial analysis, clinical data processing | Enhanced audit logging, additional evaluators, restricted model selection, DLP policies |

#### Step 2: Define Model Access Policies

Use Azure Policy to control which models are available:

```
Policy Recommendations:
├── Allow: Azure OpenAI models (GPT-4o, GPT-4.1, o3)
├── Allow: Specific third-party models evaluated for compliance
├── Restrict: Models without safety training for regulated workloads
├── Block: Models from providers without data processing agreements
└── Require: All model access through the AI Gateway (no direct endpoint calls)
```

**The nuance:** Don't block models preemptively without evaluation. A model that's inappropriate for customer-facing agents may be perfectly suitable (and more cost-effective) for internal code generation. Use the Model Router to enforce per-workload model selection policies.

#### Step 3: Governance-as-Code

Encode policies as deployable artifacts, not manual checklists:

- **Azure Policy** — Enforce that all Foundry deployments use VNet injection, that all model endpoints are accessed through APIM, that content safety is enabled on all endpoints
- **APIM Policies** — Rate limits, token quotas, required headers, JWT validation — all enforced at the gateway
- **Foundry Evaluations** — Automated quality gates in CI/CD that block deployment if safety thresholds aren't met
- **API Center Governance** — Linting rules for MCP server schemas, required metadata fields, conformance scoring

#### Step 4: Progressive Trust

Start restrictive, then expand based on evidence:

1. **Phase 1:** New agents deploy with maximum safety filters and limited tool access. Monitor for 30 days.
2. **Phase 2:** If evaluation scores meet thresholds and no security incidents occur, expand tool access and relax filters.
3. **Phase 3:** Mature agents with proven track records get fast-tracked through governance review.
4. **Phase 4:** Agents that demonstrate consistent safety can be certified for broader consumption in the catalog.

### The Role of Threat Modeling in Policy Design

Threat modeling (using frameworks like STRIDE adapted for AI) helps make informed decisions:

| Threat | Question | Policy Response |
|--------|----------|-----------------|
| **Spoofing** | Can an attacker impersonate an authorized agent? | Mutual TLS, signed Agent Cards, JWT validation |
| **Tampering** | Can request/response data be modified in transit? | TLS everywhere, APIM request/response validation |
| **Repudiation** | Can agents deny performing actions? | Immutable audit logs, correlation IDs, Application Insights |
| **Information Disclosure** | Can agents leak sensitive data? | Content Safety output filters, Groundedness Detection, DLP |
| **Denial of Service** | Can attackers overwhelm agent infrastructure? | APIM rate limiting, token quotas, circuit breaking |
| **Elevation of Privilege** | Can agents access resources beyond their scope? | Least-privilege managed identities, RBAC, tool allow-lists |

---

## Platform Architecture

The platform is organized into **five horizontal layers**, each addressing a specific concern. From top to bottom:

### Layer 1: User, Channel & Discovery Layer

This is where users interact with agents. The platform supports multiple channels:

| Channel | Description |
|---------|-------------|
| **M365 Copilot** | Custom engine agents surface directly in Microsoft 365 Copilot chat |
| **Microsoft Teams** | Agents appear as bots in Teams channels, group chats, and 1:1 conversations |
| **Custom React UI** | A purpose-built discovery portal for browsing agents, MCP tools, and skills |
| **Headless / API** | Programmatic access for SDLC tools, CI/CD pipelines, and automation |
| **Agent Discovery UI** | A portal for discovering and composing agents using A2A protocol |

### Layer 2: Enterprise Agency Platform / Agency Hub

The central nervous system of the platform:

- **Enterprise Catalog** — A governed registry of all agents, MCP tools, skills, and knowledge assets. Think of it as an "app store" for AI capabilities.
- **Agent Collaboration Mesh** — Enables agents to discover, delegate to, and orchestrate other agents using the Agent-to-Agent (A2A) protocol.
- **Developer + Admin Portal** — Where developers publish and certify agents, and administrators manage usage, cost, and access.
- **Internal Agents** — Organization-built agents for research, procurement, clinical trials, manufacturing, market access, and data.
- **External / Partner Agents** — Third-party agents from AWS, Google, and partner ecosystems that are registered and governed through the same platform.
- **Network & Access** — Azure Front Door, Private Link, and VNet injection ensure all traffic stays within the enterprise network boundary.

### Layer 3: Governance, Security & Observability Plane

This cross-cutting layer ensures every interaction is trusted and auditable:

| Component | Purpose |
|-----------|---------|
| **Microsoft Agent 365** | Centralized agent control plane — unified registry of all agents, lifecycle governance, role-specific observe/govern/secure dashboards for admins and security leaders |
| **Microsoft Defender** | AI agent inventory, risk assessment, and threat detection |
| **Azure Monitor** | Metrics, logs, and distributed tracing for all agent interactions |
| **Foundry Evaluations** | Automated quality and safety evaluation of agent outputs |
| **Content Safety** | Real-time moderation of prompts and completions (Prompt Shields, Groundedness Detection, Task Adherence) |
| **Responsible AI** | Guardrails for fairness, transparency, and accountability |
| **Red Teaming Pipeline** | Automated adversarial testing integrated into CI/CD |
| **Audit Logs** | Immutable record of all agent actions for compliance |
| **Policy Enforcement** | Azure Policy and APIM policies for governance-as-code |

### Layer 4: AI Gateway & Agent Connectivity Layer (Central Control Plane)

This is the **heart of the platform** — the AI Gateway built on Azure API Management (APIM). It serves two primary purposes:

#### Purpose 1: Centralized LLM Gateway

All LLM API calls flow through the AI Gateway, providing:

- **Single Entry Point** — Developers get one endpoint for all LLM interactions, regardless of provider (Azure OpenAI, Anthropic Claude, AWS Bedrock, Google Gemini)
- **Unified Model API** — A single OpenAI-compatible endpoint that translates requests to any backend model format automatically
- **Model Router** — A trained language model that intelligently routes prompts in real time to the most suitable LLM based on complexity, cost, and quality requirements
- **Token Rate Limiting & Quotas** — Per-consumer, per-team, per-application token limits
- **Semantic Caching** — Reuse completions for semantically similar prompts, reducing cost and latency
- **Load Balancing** — Round-robin, weighted, priority-based, and session-aware distribution across model endpoints
- **Circuit Breaking** — Automatic failover with dynamic retry-after handling
- **Content Safety** — Inline prompt moderation via Azure AI Content Safety
- **Managed Identity Authentication** — No API keys needed; APIM authenticates to backends using managed identities

#### Purpose 2: MCP Server & A2A Agent Gateway

The AI Gateway also serves as the central hub for agent interoperability:

- **Expose MCP Servers** — Any REST API managed in APIM can be exposed as an MCP server, making existing APIs instantly available as agent tools
- **Govern MCP Servers** — Rate limiting, authentication, IP filtering, and caching policies apply to all MCP tool calls
- **Secure MCP Access** — Both inbound (MCP client to APIM) and outbound (APIM to backend) secured with JWT validation, OAuth, and managed identities
- **Monitor MCP Traffic** — Application Insights integration for request/response telemetry and correlation
- **Import A2A Agent APIs** — Register A2A-compliant agents in the gateway for centralized governance
- **Passthrough MCP** — Existing MCP servers (LangChain, Azure Functions, Logic Apps) can be fronted by APIM for governance

#### Azure API Center: The Global Registry

Azure API Center sits alongside the AI Gateway to provide:

- **Centralized MCP Server Registry** — All MCP servers (both APIM-hosted and external) registered in one place
- **Skill Discovery** — Skills and plugins registered and discoverable through the API Center portal
- **API Governance** — Linting, analysis, and conformance checking for API definitions
- **Developer Portal** — Self-service discovery for developers across the organization
- **Copilot Studio Connector** — Extend agent capabilities directly from the catalog

### Layer 5: Memory & Learning Layer

Agents need persistent memory to be truly useful:

- **Long-Term Agent Memory** — Cross-session knowledge that persists indefinitely
- **Semantic Memory** — Vector-based retrieval for relevant context
- **Episodic Memory** — Conversation-specific context that maintains coherence
- **Durable Execution** — Azure Durable Functions for long-running agent workflows with checkpointing
- **Human Feedback Loop** — Mechanisms for users to correct and improve agent behavior
- **Planning + Reflection** — Agents can plan multi-step tasks and reflect on outcomes

---

## Key Design Principles

### 1. Zero-Trust Networking

Every component is deployed with network isolation:

- APIM uses **VNet injection (Premium v2 tier)** with a delegated subnet
- Foundry uses **BYO VNet** with delegated subnets and private endpoints
- App Services use **App Service Environment (ASE)** with VNet injection
- All inter-service communication uses **private endpoints**
- No public endpoints are exposed (internal mode for APIM)

### 2. Identity-First Security

- **Microsoft Entra ID** for all authentication and authorization
- **Managed Identities** eliminate API keys entirely
- **On-Behalf-Of (OBO)** flows preserve user identity through agent chains
- **Azure RBAC** for fine-grained access control at every layer

### 3. Governance by Default

- Every agent, tool, and skill must be registered in the Enterprise Catalog
- Azure Policy enforces deployment standards
- Content Safety is applied to all LLM interactions
- Token quotas prevent runaway costs
- Red teaming validates safety before production deployment

### 4. Developer Self-Service

- Developers discover and consume agents without filing tickets
- Single SDK endpoint for all LLM calls
- MCP tools are discoverable and immediately usable
- Agent Framework provides consistent development experience
- Progressive trust model rewards proven agents with expanded access

### 5. Multi-Model, Multi-Provider

- Unified Model API abstracts provider differences
- Model Router optimizes cost/quality automatically
- No vendor lock-in — switch models without code changes
- Policy controls which models are available per workload

### 6. Defense in Depth

- Multiple overlapping security controls at every layer
- Content Safety at the gateway (pre-model and post-model)
- Defender for AI at the infrastructure level
- Red teaming at the application level
- Human-in-the-loop for critical decisions

---

## Technology Stack

| Layer | Technologies |
|-------|-------------|
| **Frontend** | React, Microsoft Teams SDK, M365 Copilot Extensions |
| **Agent Runtime** | Microsoft Agent Framework (Python), Azure Functions Serverless Agents |
| **Orchestration** | Azure Durable Functions, Foundry Agent Service |
| **AI Gateway** | Azure API Management (Premium v2), Azure API Center |
| **Models** | Azure OpenAI, Anthropic Claude, AWS Bedrock, Google Gemini |
| **Knowledge (IQ)** | Foundry IQ, Work IQ, Fabric IQ, Web IQ, Azure AI Search |
| **Memory** | Cosmos DB, Azure Blob Storage, Local Storage |
| **Networking** | Azure VNet, Private Link, Azure Firewall, App Service Environment |
| **Security** | Microsoft Defender for AI, Microsoft Agent 365, Azure Content Safety, Prompt Shields, Task Adherence |
| **Observability** | Azure Monitor, Application Insights, Microsoft Agent 365 (Observe), Foundry Evaluations, OpenTelemetry |
| **Governance** | Microsoft Agent 365 (Govern), Azure Policy, Microsoft Purview, Audit Logs, API Center Linting |
| **IaC** | Bicep, Azure CLI, Azure Developer CLI (azd) |

---

## Lab Flow

```
Chapter 01: Microsoft Foundry (BYO VNet)
    │
    ├── Create Foundry with private networking
    ├── Configure delegated subnets
    ├── Establish private endpoints and DNS
    │
    ▼
Chapter 02: AI Gateway (APIM)
    │
    ├── Set up APIM with VNet injection
    ├── Configure GenAI gateway capabilities
    ├── Create unified model API
    ├── Expose REST API as MCP server
    │
    ▼
Chapter 03: Agent Framework
    │
    ├── Build agent with Microsoft Agent Framework
    ├── Add memory and harness
    ├── Expose via A2A protocol
    │
    ▼
Chapter 04: API Center
    │
    ├── Create Azure API Center
    ├── Register MCP servers and skills
    │
    ▼
Chapter 05: React Discovery UI
    │
    ├── Build React app for agent/tool discovery
    ├── Deploy to App Service Environment
    │
    ▼
Chapter 06: Foundry IQ Knowledge Base
    │
    ├── Create and configure knowledge index
    │
    ▼
Chapter 07: Prompt Agent
    │
    ├── Build prompt agent with KB + MCP + A2A
    │
    ▼
Chapter 08: Hosted Agent
    │
    ├── Deploy Agent Framework agent as hosted agent
    ├── Expose hosted agent via A2A in APIM
    │
    ▼
Chapter 09: Work IQ ──▶ Chapter 10: Serverless Agent
    │                         │
    ▼                         ▼
Chapter 11: Fabric IQ    Chapter 12: Model Router
    │                         │
    └────────┬────────────────┘
             ▼
Chapter 13: M365 Custom Engine Agent
    │
    ▼
Chapter 14: Copilot Studio VNet Integration
    │
    ▼
Chapter 15: Observability & Evaluation
    │
    ▼
Chapter 16: Microsoft Defender
    │
    ▼
═══════════════════════════════════════════════
  PART 2: SECURE AGENT FACTORY (SAF)
═══════════════════════════════════════════════
    │
    ▼
Chapter 17: Enterprise Roles & Responsibilities
    │
    ▼
Chapter 18: AI Governance Policy & Standards
    │
    ▼
Chapter 19: Network Foundation & Security
    │
    ▼
Chapter 20: Observability & Evaluation Pipeline
    │
    ▼
Chapter 21: SAF Blueprint Deployment
    │
    ▼
Chapter 22: Identity, Auth & Secrets Management
    │
    ▼
Chapter 23: Governed Tools & Model Registry
    │
    ▼
Chapter 24: Developer Experience & Self-Service
    │
    ▼
Chapter 25: CI/CD Gates & Automated Governance
    │
    ▼
Chapter 26: End-to-End Scenario Validation
    │
    ▼
═══════════════════════════════════════════════
  PART 3: CAPSTONE & DAY-IN-LIFE
═══════════════════════════════════════════════
    │
    ▼
Chapter 27: Governed Developer Journey (Capstone)
    │
    ▼
Chapter 28: Day in the Life — AI CoE
    │
    ▼
Chapter 29: Day in the Life — IT Platform Engineering
```

---

## Next Steps

Proceed to [Chapter 01 — Create Microsoft Foundry with BYO Networking](./01-foundry-byo-networking.md) to begin building the platform foundation.
