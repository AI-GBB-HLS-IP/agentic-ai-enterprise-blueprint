# Microsoft Secure Internet of Agents — Enterprise Lab Guide

## 🏗️ Building a Highly Secure Enterprise Agentic AI Platform

---

## Vision

> Create an enterprise-scale Agentic AI Platform that enables developers across the entire organization to seamlessly **discover, consume, and orchestrate** repeatable Agents, Tools, Skills, and Knowledge Assets — without the complexity of authentication, connectivity, or infrastructure management.

> Provide a **global, governed marketplace** of reusable Agents, Tools, and Skills with rich discoverability, enabling both developers and business users to rapidly build, compose, and deploy agentic applications across all cloud providers.

> Deliver **built-in Security, Tokenomics, Observability, Governance, and Compliance** by design, ensuring every AI interaction is trusted, measurable, optimized, and enterprise-ready.

---

## Lab Chapters

| Chapter | Title | Focus |
|---------|-------|-------|
| [00](./chapters/00-overview.md) | Platform Overview & Architecture | Architecture deep-dive, IQ ecosystem, security, governance philosophy |
| [01](./chapters/01-foundry-byo-networking.md) | Create Microsoft Foundry with BYO Networking | Foundry instance with private virtual network, delegated subnets |
| [02](./chapters/02-ai-gateway.md) | Build the AI Gateway | APIM setup, networking, GenAI gateway, unified model API, MCP server |
| [03](./chapters/03-agent-framework.md) | Build an Agent with Microsoft Agent Framework | Create agent, memory, harness, expose via A2A |
| [04](./chapters/04-api-center.md) | Create Azure API Center | Centralized registry for MCP servers, skills, and APIs |
| [05](./chapters/05-react-discovery-ui.md) | Build a React Discovery UI | Custom UI for agents, MCP tools, and skills discovery |
| [06](./chapters/06-foundry-iq-knowledge.md) | Create a Foundry IQ Knowledge Base | Enterprise knowledge grounding for agents |
| [07](./chapters/07-prompt-agent.md) | Build a Prompt Agent in Foundry | Agent with knowledge base, MCP tools, and A2A calls |
| [08](./chapters/08-hosted-agent.md) | Build a Hosted Agent in Foundry | Deploy Agent Framework agent as hosted agent, expose via A2A in APIM |
| [09](./chapters/09-work-iq.md) | Connect Your Agent with Work IQ | Microsoft 365 data grounding with BYO networking considerations |
| [10](./chapters/10-serverless-agent.md) | Create a Serverless Agent with Azure Functions | Event-driven agents with the serverless agents runtime |
| [11](./chapters/11-fabric-iq.md) | Connect Your Agent with Fabric IQ (Optional) | Lakehouse, ontology, and Fabric IQ integration |
| [12](./chapters/12-model-router.md) | Create a Model Router in Foundry | Intelligent prompt routing across multiple LLMs |
| [13](./chapters/13-m365-custom-engine.md) | Expose as Custom Engine Agent in M365 | Surface hosted agent in Microsoft 365 Copilot and Teams |
| [14](./chapters/14-observability.md) | Observability, Evaluation & Red Teaming (Optional) | Monitoring dashboards, evaluators, guardrails, red teaming |
| [15](./chapters/15-defender.md) | Implement Microsoft Defender for AI | AI agent inventory, risk assessment, threat detection |
| [16](./chapters/16-developer-journey.md) | The Developer Journey | End-to-end scenario: from discovery to deployment |

---

## Prerequisites

- Azure subscription with Owner or Contributor access
- Microsoft 365 Copilot license (for Work IQ and M365 chapters)
- Microsoft Fabric capacity (for Fabric IQ chapter)
- Azure CLI installed and authenticated
- Visual Studio Code with GitHub Copilot extension
- Python 3.11+ and Node.js 20+
- Docker Desktop (for container deployments)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    User, Channel & Discovery Layer                  │
│  M365 Copilot │ Teams │ Custom React UI │ Headless API │ Portals  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│              Enterprise Agency Platform / Agency Hub                 │
│                                                                     │
│  ┌──────────────┐  ┌─────────────────────┐  ┌───────────────────┐  │
│  │  Enterprise   │  │ Agent Collaboration │  │  Developer +      │  │
│  │  Catalog      │  │ Mesh (A2A)          │  │  Admin Portal     │  │
│  │  • Agent Reg  │  │ • Discovery         │  │  • Marketplace    │  │
│  │  • MCP Tools  │  │ • Delegation        │  │  • Publish/Certify│  │
│  │  • Skills     │  │ • Orchestration     │  │  • Usage + Cost   │  │
│  │  • Knowledge  │  │                     │  │                   │  │
│  └──────────────┘  └─────────────────────┘  └───────────────────┘  │
│                                                                     │
│  Internal Agents                    External / Partner Agents       │
│  • Research, Procurement, Data      • AWS, Google, 3rd-party       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│          Governance, Security & Observability Plane                  │
│  Microsoft Defender │ Azure Monitor │ Foundry Evaluations │         │
│  Content Safety │ Responsible AI │ Guardrails │ Audit Logs │ Policy │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│     AI Gateway & Agent Connectivity Layer (Central Control Plane)    │
│                                                                     │
│  ┌───────────┐    ┌───────────────────────┐    ┌─────────────────┐ │
│  │ REST APIs  │───▶│  Azure API Center     │    │ Runtime Controls│ │
│  │ MCP Endpts │───▶│  • API Center         │    │ • Model routing │ │
│  │ Agent Endpts│──▶│  • MCP Registry       │───▶│ • Semantic cache│ │
│  │ A2A Endpts │   │  • Tool Catalog       │    │ • Load balancing│ │
│  └───────────┘    │  • Tool Discovery     │    │ • Token optimize│ │
│                    └───────────┬───────────┘    │ • Rate limiting │ │
│                                │                │ • AuthN/AuthZ   │ │
│                    ┌───────────▼───────────┐    │ • Policy controls│ │
│                    │   AI Gateway (APIM)    │    └─────────────────┘ │
│                    │   • VNet Injection     │                        │
│                    │   • Private Endpoints  │───▶ Azure OpenAI      │
│                    │   • MCP Gateway        │───▶ Azure AI Models   │
│                    │   • A2A Broker         │───▶ Anthropic Claude  │
│                    └───────────────────────┘───▶ AWS Bedrock        │
│                                              ───▶ Google Gemini     │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                   Memory & Learning Layer                            │
│  Long-Term Agent Memory ──▶ Semantic Memory ──▶ Episodic Memory     │
│  ──▶ Durable Execution ──▶ Human Feedback Loop ──▶ Planning +       │
│      Reflection                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Network Architecture (Zero-Trust)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Enterprise Network Boundary                   │
│                                                                 │
│  ┌──────────────────────┐    ┌──────────────────────────────┐  │
│  │   Hub VNet            │    │  Spoke VNet (AI Platform)    │  │
│  │   • Azure Firewall    │◄──▶│  • APIM Subnet (delegated)  │  │
│  │   • Azure Bastion     │    │  • App Service Subnet        │  │
│  │   • VPN/ExpressRoute  │    │  • Foundry Delegated Subnet  │  │
│  │   • DNS Forwarders    │    │  • Private Endpoint Subnet   │  │
│  └──────────────────────┘    │  • ACA Subnet                │  │
│                               └──────────────────────────────┘  │
│                                                                 │
│  Private DNS Zones:                                             │
│  • privatelink.azure-api.net    • privatelink.openai.azure.com │
│  • privatelink.blob.core.windows.net                           │
│  • privatelink.vaultcore.azure.net                             │
│  • privatelink.database.windows.net                            │
│  • privatelink.cognitiveservices.azure.com                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Getting Started

Start with [Chapter 00 — Platform Overview](./chapters/00-overview.md) for a detailed understanding of the architecture, then proceed through each chapter sequentially.

Each chapter builds on the previous one, creating an end-to-end secure Internet of Agents platform.
