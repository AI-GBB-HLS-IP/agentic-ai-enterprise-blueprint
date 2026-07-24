# Chapter 16 — Capstone: End-to-End Developer Journey

## Objective

Walk through the **complete developer journey** from "I want to build a complex multi-agent application" to production deployment — demonstrating how all 15 previous chapters come together into a unified platform experience.

---

## The Scenario

**Alex**, a developer on the Customer Success team, needs to build a **Customer Onboarding Assistant** — a multi-agent application that:

1. Greets new customers and collects requirements
2. Checks available products against the customer's industry and region
3. Generates a personalized onboarding plan
4. Schedules kickoff meetings with the right team members
5. Creates support tickets for any special requirements

Alex has never built an agentic application before. Here's how the Internet of Agents platform makes this possible in a single day.

---

## Phase 1: Discover (30 minutes)

### Step 1: Browse the API Center Portal

Alex opens the **Developer Self-Service Portal** (Chapter 04):

```
https://portal.agents.contoso.com
```

The portal shows three tabs:

| Tab | What Alex Finds |
|-----|----------------|
| **Agents** | EnterpriseTravelAgent, PolicyAdvisor, HRBot — reusable agents with A2A endpoints |
| **MCP Servers** | enterprise-tools, expense-api, crm-tools, calendar-api — available tool servers |
| **Skills** | policy-lookup, employee-search, ticket-creation — composable capabilities |

### Step 2: Find Relevant Assets

Alex searches for "customer" and "onboarding":

**Agents found**:
- `CRMAgent` — manages customer records (A2A endpoint available)
- `CalendarAgent` — schedules meetings (A2A endpoint available)

**MCP Servers found**:
- `crm-tools` — customer lookup, account creation, product catalog
- `calendar-api` — schedule meetings, check availability
- `ticketing-api` — create and manage support tickets

**Skills found**:
- `industry-compliance-check` — validates product eligibility by region

### Step 3: Review Documentation

Each asset has auto-generated documentation from API Center metadata:

```
crm-tools MCP Server
├── Tools:
│   ├── get_customer(id) → CustomerProfile
│   ├── list_products(industry, region) → Product[]
│   ├── create_account(customer) → AccountId
│   └── get_onboarding_template(product) → Template
├── Authentication: Managed Identity via APIM
├── Rate Limit: 100 req/min
└── API Gateway: https://apim-agents-gateway.azure-api.net/mcp/crm-tools/mcp
```

---

## Phase 2: Build (2 hours)

### Step 1: Create the Agent Project

Alex uses GitHub Copilot Agent Mode to scaffold the project:

```
@workspace Create a new Agent Framework project called "customer-onboarding-agent" 
that uses MCP tools for CRM and calendar operations. Include A2A server setup.
```

Generated project structure:

```
customer-onboarding-agent/
├── agent.py                  # Main agent definition
├── a2a_server.py             # A2A server for inter-agent communication
├── requirements.txt          # Dependencies
├── Dockerfile                # Container image
├── .env.sample               # Environment template
└── tests/
    ├── test_agent.py
    └── test_integration.py
```

### Step 2: Define the Agent

```python
# agent.py
import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from agent_framework import Agent, FoundryChatClient
from agent_framework.tools import McpServer
from agent_framework.memory import LocalFileMemory

load_dotenv()

# Connect to the AI Gateway (APIM)
chat_client = FoundryChatClient(
    endpoint=os.environ["APIM_GATEWAY_URL"],
    model="model-router",  # Smart routing across models
    api_version="2025-11-18",
)

# Connect MCP tools (discovered from API Center)
crm_tools = McpServer(
    name="crm-tools",
    url=f"{os.environ['APIM_GATEWAY_URL']}/mcp/crm-tools/mcp",
)

calendar_tools = McpServer(
    name="calendar-api",
    url=f"{os.environ['APIM_GATEWAY_URL']}/mcp/calendar-api/mcp",
)

ticketing_tools = McpServer(
    name="ticketing-api",
    url=f"{os.environ['APIM_GATEWAY_URL']}/mcp/ticketing-api/mcp",
)

# Create the agent
onboarding_agent = Agent(
    name="CustomerOnboardingAgent",
    instructions="""You are a Customer Onboarding Assistant. Your job is to 
guide new customers through the onboarding process.

Workflow:
1. Greet the customer and ask for their company name and industry
2. Use crm-tools to look up existing customer records
3. Use crm-tools to list available products for their industry and region
4. Generate a personalized onboarding plan
5. Use calendar-api to schedule a kickoff meeting with the success team
6. Use ticketing-api to create any necessary support tickets
7. Summarize the onboarding plan for the customer

For complex CRM operations, delegate to the CRMAgent via A2A.
For scheduling, delegate to the CalendarAgent via A2A.

Always be professional, thorough, and proactive.""",
    chat_client=chat_client,
    tools=[crm_tools, calendar_tools, ticketing_tools],
    memory=LocalFileMemory("./agent_memory"),
)
```

### Step 3: Add A2A Communication

```python
# a2a_server.py
from agent_framework.a2a import create_a2a_server, AgentCard, Skill

server = create_a2a_server(
    agent=onboarding_agent,
    card=AgentCard(
        name="CustomerOnboardingAgent",
        description="Guides new customers through personalized onboarding",
        url="https://app-onboarding-agent.azurewebsites.net",
        skills=[
            Skill(
                name="onboard_customer",
                description="Complete customer onboarding with CRM, calendar, and tickets",
                input_schema={
                    "type": "object",
                    "properties": {
                        "company_name": {"type": "string"},
                        "industry": {"type": "string"},
                        "region": {"type": "string"},
                    },
                    "required": ["company_name"],
                },
            ),
        ],
    ),
)
```

### Step 4: Test Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Run the interactive harness
python -m agent_framework.harness agent:onboarding_agent

# Test queries:
# > "I'm starting onboarding for Acme Corp, they're in manufacturing in EMEA"
# > "What products are available for them?"
# > "Schedule a kickoff meeting for next week"
```

---

## Phase 3: Evaluate (1 hour)

### Step 1: Run Quality Evaluators

```python
# tests/test_evaluation.py
from azure.ai.evaluation import GroundednessEvaluator, RelevanceEvaluator

eval_dataset = [
    {
        "query": "Onboard Acme Corp, manufacturing company in Germany",
        "expected_behavior": "Should look up CRM, list EU-compliant products, suggest onboarding plan",
    },
    {
        "query": "What products work for a fintech startup in Singapore?",
        "expected_behavior": "Should check APAC products with financial compliance",
    },
]

# Run evaluations...
print("✅ Quality gate passed")
```

### Step 2: Run Safety Gate

```python
# Run red team evaluation (from Chapter 14)
results = await red_team.scan(
    target=lambda msg: onboarding_agent.run(msg).text,
    num_objectives=20,
)
assert results.attack_success_rate < 0.05, "Safety gate failed"
print("✅ Safety gate passed")
```

---

## Phase 4: Deploy (1 hour)

### Step 1: Build and Push Container

```bash
# Build container image
az acr build \
  --registry acragentsplatform \
  --image customer-onboarding-agent:v1 \
  .
```

### Step 2: Deploy as Hosted Agent

```python
# Deploy to Foundry as a Hosted Agent (Chapter 08)
hosted_agent = project_client.agents.create_version(
    agent_name="CustomerOnboardingAgent",
    definition=HostedAgentDefinition(
        container_image="acragentsplatform.azurecr.io/customer-onboarding-agent:v1",
        container_port=8000,
        cpu=1.0,
        memory="2Gi",
        min_replicas=1,
        max_replicas=5,
    ),
)
print(f"✅ Deployed: {hosted_agent.name}")
```

### Step 3: Register in API Center

```bash
# Register the agent in API Center (Chapter 03)
az apic api register \
  --resource-group $RESOURCE_GROUP \
  --service-name "apic-agents-platform" \
  --api-id "customer-onboarding-agent" \
  --title "Customer Onboarding Agent" \
  --type "a2a" \
  --description "Guides new customers through personalized onboarding"
```

### Step 4: Register in APIM

```bash
# Import into APIM for governance (Chapter 01)
az apim api import \
  --resource-group $RESOURCE_GROUP \
  --service-name "apim-agents-gateway" \
  --api-id "customer-onboarding-agent" \
  --path "a2a/customer-onboarding" \
  --display-name "Customer Onboarding Agent" \
  --service-url "https://app-onboarding-agent.azurewebsites.net"
```

---

## Phase 5: Expose to M365 (30 minutes)

### Step 1: Create Teams Custom Engine Agent

Using the template from Chapter 13, Alex creates a Teams bot that routes to the onboarding agent:

```typescript
// Point the Teams bot to the new agent
const response = await client.chat.completions.create({
  model: "model-router",
  messages: [
    { role: "system", content: "Route to CustomerOnboardingAgent for onboarding requests." },
    { role: "user", content: userMessage },
  ],
});
```

### Step 2: Publish to Teams

```bash
npx teamsapp publish --env prod
```

Now any employee can type in Teams:
> **"@Onboarding Assistant Set up onboarding for Contoso Ltd, they're a healthcare company in the UK"**

---

## Phase 6: Monitor (Ongoing)

### Defender Dashboard

Alex's new agent immediately appears in the Defender for AI inventory (Chapter 15):

| Agent | Risk | Notes |
|-------|------|-------|
| CustomerOnboardingAgent | Low | BYO VNet, content filtering, RBAC |

### Observability

The monitoring dashboard (Chapter 14) shows:

```kql
// Alex's agent metrics
customEvents
| where customDimensions["agent.name"] == "CustomerOnboardingAgent"
| summarize
    Invocations = count(),
    AvgDuration = avg(todouble(customDimensions["agent.duration_ms"])),
    ToolCalls = sum(toint(customDimensions["agent.tools_called"])),
    SuccessRate = round(100.0 * countif(success) / count(), 2)
  by bin(timestamp, 1h)
```

---

## The Complete Platform Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER / CHANNEL LAYER                         │
│  Teams │ Outlook │ Custom Apps │ Power Platform │ CLI           │
└────────┬────────────────────────────────────────────────────────┘
         │
┌────────▼────────────────────────────────────────────────────────┐
│              AI GATEWAY (APIM Premium v2, VNet)                 │
│  Rate Limiting │ Auth │ Routing │ Logging │ Content Filtering   │
│  Model Router │ MCP Governance │ A2A Routing                   │
└────────┬────────────────────────────────────────────────────────┘
         │
┌────────▼────────────────────────────────────────────────────────┐
│                    AGENCY PLATFORM                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Foundry  │  │ Agent    │  │ Azure    │  │ M365 Custom   │  │
│  │ Prompt   │  │ Framework│  │ Functions│  │ Engine Agent  │  │
│  │ Agents   │  │ (A2A)    │  │ Agents   │  │               │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────────────┘  │
│       │              │             │               │            │
│  ┌────▼──────────────▼─────────────▼───────────────▼─────────┐ │
│  │          TOOLS / KNOWLEDGE / SKILLS                        │ │
│  │  MCP Servers │ Foundry IQ │ Work IQ │ Fabric IQ            │ │
│  └────────────────────────────────────────────────────────────┘ │
└────────┬────────────────────────────────────────────────────────┘
         │
┌────────▼────────────────────────────────────────────────────────┐
│              GOVERNANCE & SECURITY                              │
│  API Center │ Defender for AI │ Entra ID │ Key Vault            │
│  Evaluators │ Guardrails │ Red Teaming │ RBAC                  │
└────────┬────────────────────────────────────────────────────────┘
         │
┌────────▼────────────────────────────────────────────────────────┐
│              OBSERVABILITY                                      │
│  Application Insights │ Azure Monitor │ Log Analytics           │
│  Cost Tracking │ Performance Dashboards │ Alert Rules           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Developer Self-Service Summary

| What Alex Needed | Platform Provided | Chapter |
|-----------------|-------------------|---------|
| Find reusable tools | API Center portal with search | 03, 04 |
| Build agent with tools | Agent Framework + MCP | 02 |
| Test locally | Interactive harness | 02 |
| Smart model selection | Model Router | 12 |
| Enterprise knowledge | Foundry IQ knowledge base | 06 |
| M365 data access | Work IQ | 09 |
| Evaluate quality | Built-in evaluators | 14 |
| Safety testing | Red teaming pipeline | 14 |
| Deploy securely | Hosted Agent in BYO VNet | 05, 08 |
| Expose in Teams | Custom Engine Agent | 13 |
| Monitor in production | App Insights + dashboards | 14 |
| Security posture | Defender for AI | 15 |
| Governance | APIM policies + guardrails | 01, 14 |

---

## Key Takeaways

1. **Developer Self-Service**: Alex built a production agent without knowing about VNets, authentication, or infrastructure. The platform abstracted all complexity.

2. **Composability**: By reusing existing MCP servers and A2A agents, Alex avoided rebuilding CRM, calendar, and ticketing integrations.

3. **Security by Default**: Zero-trust networking, content filtering, and RBAC were inherited from the platform. Alex didn't need to configure security.

4. **Governance Built-In**: APIM policies automatically applied rate limiting, logging, and content safety to Alex's agent.

5. **Observable from Day One**: Monitoring, alerting, and cost tracking were immediate — no additional instrumentation required.

6. **Multi-Modal Deployment**: The same agent runs in Foundry, is accessible via A2A, queryable via APIM, and usable in Teams — from a single codebase.

---

## What's Next

With the Internet of Agents platform operational, consider:

- **Scaling**: Add more MCP servers for new enterprise systems
- **Federated Governance**: Extend API Center with custom metadata schemas per business unit
- **Multi-Region**: Deploy Foundry and APIM in multiple regions for global availability
- **Advanced Patterns**: Implement supervisor agents that orchestrate multiple sub-agents
- **Cost Optimization**: Use Model Router analytics to fine-tune routing modes per agent
- **Compliance**: Add industry-specific guardrails (HIPAA, PCI-DSS, SOC 2)

---

## Congratulations! 🎉

You have built an **Enterprise-Scale Agentic AI Platform** that enables developers across your organization to seamlessly discover, consume, and orchestrate repeatable Agents, Tools, Skills, and Knowledge Assets — without the complexity of authentication, connectivity, or infrastructure management.

---

## References

All chapters reference their respective Microsoft Learn documentation. For the complete reference list, see:

| Chapter | Topic | Key Reference |
|---------|-------|---------------|
| 00 | Architecture Overview | Platform design document |
| 01 | AI Gateway | [APIM GenAI Gateway](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities) |
| 02 | Agent Framework | [Microsoft Agent Framework](https://learn.microsoft.com/en-us/azure/foundry/agent-framework/) |
| 03 | API Center | [Azure API Center](https://learn.microsoft.com/en-us/azure/api-center/) |
| 04 | Discovery UI | [API Center Portal](https://learn.microsoft.com/en-us/azure/api-center/enable-api-center-portal) |
| 05 | Foundry + VNet | [Foundry Networking](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive) |
| 06 | Foundry IQ | [Foundry IQ Connect](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/foundry-iq-connect) |
| 07 | Prompt Agent | [Prompt Agent Quickstart](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/prompt-agent) |
| 08 | Hosted Agent | [Deploy Hosted Agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-code) |
| 09 | Work IQ | [Work IQ Overview](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/work-iq/overview) |
| 10 | Serverless Agent | [Serverless Agents Runtime](https://learn.microsoft.com/en-us/azure/azure-functions/scenario-serverless-agents-runtime) |
| 11 | Fabric IQ | [Fabric IQ Overview](https://learn.microsoft.com/en-us/fabric/iq/overview) |
| 12 | Model Router | [Model Router](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/model-router) |
| 13 | M365 Agent | [Custom Engine Agent](https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/overview-custom-engine-agent) |
| 14 | Observability | [AI Evaluation](https://learn.microsoft.com/en-us/azure/ai-studio/concepts/evaluation-approach-gen-ai) |
| 15 | Defender | [Defender for AI](https://learn.microsoft.com/en-us/defender-xdr/security-for-ai-overview) |
| 16 | Developer Journey | This chapter |
