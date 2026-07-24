# Chapter 07 — Build a Prompt Agent in Foundry

## Objective

Build a **Prompt Agent** in Microsoft Foundry that combines the knowledge base from Chapter 06, makes MCP tool calls via APIM (Chapter 02), and communicates with the Agent Framework agent via A2A (Chapter 03).

---

## Architecture Context: The Fully-Connected Agent

### Where This Fits

The Prompt Agent demonstrates the **power of composition** — a single agent that leverages all three intelligence channels simultaneously: knowledge retrieval (Foundry IQ), tool execution (MCP via APIM), and agent delegation (A2A).

### What You Will Achieve

- An agent that **retrieves knowledge** from Foundry IQ before responding
- The same agent **calling external tools** via MCP through the governed AI Gateway
- The same agent **delegating to other agents** via A2A when tasks fall outside its expertise
- A fully managed deployment (no infrastructure to maintain)

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Compound Intelligence** | Combine knowledge, tools, and other agents in a single coherent experience |
| **No Infrastructure** | Prompt agents are fully managed — no containers, no scaling, no patching |
| **Governed Tool Access** | All MCP tool calls route through APIM with full policy enforcement |
| **Agent Collaboration** | Delegate complex sub-tasks to specialized agents rather than building everything in one monolith |
| **Rapid Iteration** | Change agent behavior by editing prompts and tool configurations — no redeployment needed |

---

## Prerequisites

- Chapters 01-06 completed
- Foundry project with BYO VNet
- Knowledge index operational
- APIM MCP server accessible
- A2A travel agent deployed

---

## Part 1: Understanding Prompt Agents

**Prompt Agents** are fully managed by Microsoft:
- No container image or infrastructure management required
- Compute and scaling are automatic
- You define behavior through configuration and instructions
- All tool calls route through the **single-tenant data proxy**
- Prompt agent revisions do NOT consume IPs from the delegated subnet

---

## Part 2: Create the Prompt Agent

### Step 1: Create via Python SDK

```python
import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    PromptAgentDefinition,
    FoundryIQTool,
    McpTool,
)

load_dotenv()

endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"]
model = os.environ["FOUNDRY_MODEL_NAME"]  # e.g., "gpt-4o"

with (
    DefaultAzureCredential() as credential,
    AIProjectClient(endpoint=endpoint, credential=credential) as project_client,
):
    # Configure tools
    # 1. Foundry IQ knowledge base
    knowledge_tool = FoundryIQTool(
        index_name="enterprise-policies",
        description="Search enterprise travel and expense policies",
    )

    # 2. MCP tool via APIM (from Chapter 02)
    mcp_tool = McpTool(
        server_url="https://apim-agents-gateway.azure-api.net/mcp/enterprise-tools/mcp",
        server_label="Enterprise Tools",
        description="Access enterprise HR and IT tools",
        # Authentication handled via project connection
        connection_id="<apim-connection-id>",
    )

    # Create the prompt agent
    agent = project_client.agents.create_version(
        agent_name="EnterprisePolicyAdvisor",
        definition=PromptAgentDefinition(
            model=model,
            instructions="""You are an Enterprise Policy Advisor agent.

Your capabilities:
1. **Policy Lookup**: Use the Foundry IQ knowledge base to answer questions 
   about travel and expense policies. Always cite the specific policy section.

2. **Employee Lookup**: Use the enterprise-tools MCP server to look up 
   employee details when needed for travel approvals.

3. **Ticket Creation**: Use the enterprise-tools MCP server to create 
   support tickets for policy exceptions or special requests.

4. **Travel Agent Delegation**: For actual flight/hotel bookings, delegate 
   to the Enterprise Travel Agent via A2A.

Guidelines:
- Always check the policy before approving any travel request
- Provide specific policy references in your answers
- If a request violates policy, explain why and suggest alternatives
- Be professional, concise, and helpful""",
            tools=[knowledge_tool, mcp_tool],
        ),
    )

    print(f"Agent created: {agent.name} (version: {agent.version})")
```

### Step 2: Test the Agent

```python
    # Get OpenAI client for agent interaction
    openai_client = project_client.get_openai_client()

    # Test 1: Policy question (uses Foundry IQ)
    response = openai_client.responses.create(
        input="What is the maximum hotel rate for a trip to Paris?",
        extra_body={
            "agent_reference": {
                "name": agent.name,
                "type": "agent_reference",
            }
        },
    )
    print(f"\nPolicy Query Response:\n{response.output_text}")

    # Test 2: Employee lookup (uses MCP tool via APIM)
    response = openai_client.responses.create(
        input="Look up the details for Jane Doe in the employee directory",
        extra_body={
            "agent_reference": {
                "name": agent.name,
                "type": "agent_reference",
            }
        },
    )
    print(f"\nEmployee Lookup Response:\n{response.output_text}")

    # Test 3: Create a ticket (uses MCP tool via APIM)
    response = openai_client.responses.create(
        input="Create a support ticket for a policy exception: I need to book business class for a 3-hour domestic flight due to a medical condition",
        extra_body={
            "agent_reference": {
                "name": agent.name,
                "type": "agent_reference",
            }
        },
    )
    print(f"\nTicket Creation Response:\n{response.output_text}")
```

---

## Part 3: Add A2A Call to the Travel Agent

To call the Enterprise Travel Agent (from Chapter 03) via A2A, register it as a tool server in your Foundry project:

### Step 1: Create a Connection to the A2A Agent

1. In Foundry Portal → **Settings** → **Connections** → **+ New Connection**
2. Select **A2A Agent**
3. Configure:
   - **Name**: `travel-agent-a2a`
   - **Endpoint**: `https://app-travel-agent.azurewebsites.net`
   - **Authentication**: Managed Identity or API Key

### Step 2: Add A2A as a Tool Server

```python
# Register the A2A agent as a tool server
project_client.connections.create_or_update(
    name="travel-agent-a2a",
    connection_type="a2a",
    target="https://app-travel-agent.azurewebsites.net",
    credentials={"type": "managed_identity"},
)
```

### Step 3: Update Agent Instructions

Update the agent to include A2A delegation:

```python
agent = project_client.agents.create_version(
    agent_name="EnterprisePolicyAdvisor",
    definition=PromptAgentDefinition(
        model=model,
        instructions="""You are an Enterprise Policy Advisor agent.

Your capabilities:
1. **Policy Lookup**: Search enterprise policies via Foundry IQ knowledge base.
2. **Employee Lookup**: Look up employees via the enterprise-tools MCP server.
3. **Ticket Creation**: Create support tickets via the enterprise-tools MCP server.
4. **Travel Booking**: For actual bookings, delegate to the Enterprise Travel Agent.
   Use the travel-agent-a2a tool server for flight and hotel bookings.

Workflow for travel requests:
1. First, check the travel policy using Foundry IQ
2. Verify the employee's travel authorization level
3. If policy-compliant, delegate booking to the Travel Agent via A2A
4. If not compliant, explain the policy and create an exception ticket""",
        tools=[knowledge_tool, mcp_tool],
    ),
)
```

### Step 4: Test End-to-End

```python
# Full workflow test
response = openai_client.responses.create(
    input="""I'm Jane Doe from Engineering. I need to travel to Paris 
    next Tuesday for a 3-day conference. Please check the travel policy, 
    find suitable flights and hotels, and help me with the booking.""",
    extra_body={
        "agent_reference": {
            "name": agent.name,
            "type": "agent_reference",
        }
    },
)
print(f"\nFull Workflow Response:\n{response.output_text}")
```

Expected flow:
1. Agent queries Foundry IQ for travel policy → finds Paris per diem and hotel rates
2. Agent calls MCP tool to look up Jane Doe → confirms department and authorization
3. Agent delegates to Travel Agent via A2A → gets flight and hotel options
4. Agent responds with policy-compliant recommendations

---

## Summary

| Component | Status |
|-----------|--------|
| Prompt Agent created in Foundry | ✅ |
| Foundry IQ knowledge base connected | ✅ |
| MCP tool calls via APIM working | ✅ |
| A2A delegation to Travel Agent configured | ✅ |
| End-to-end workflow tested | ✅ |

---

## References

- [Prompt Agent Quickstart](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/prompt-agent?tabs=python)
- [Foundry IQ Connect](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/foundry-iq-connect)

---

## Next Steps

Proceed to [Chapter 08 — Build a Hosted Agent in Foundry](./08-hosted-agent.md)
