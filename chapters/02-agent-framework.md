# Chapter 02 — Build an Agent with Microsoft Agent Framework

## Objective

In this chapter, you will build an AI agent using the **Microsoft Agent Framework**, add persistent memory, create a test harness, deploy it to Azure App Service (and optionally Azure Container Apps), and expose it via the **A2A (Agent-to-Agent) protocol** for cross-platform interoperability.

By the end of this chapter, you will have:
- A working AI agent built with Microsoft Agent Framework (Python)
- Persistent memory configured for conversation continuity
- A test harness for local development and debugging
- The agent exposed via A2A for discovery and invocation by other agents
- The agent deployed to Azure App Service

---

## Prerequisites

- Chapter 01 completed (AI Gateway operational)
- Python 3.11+ installed
- Azure OpenAI endpoint from Chapter 01
- Azure CLI authenticated

---

## Part 1: Create Your First Agent

### Step 1: Set Up the Project

```bash
# Create project directory
mkdir enterprise-travel-agent && cd enterprise-travel-agent

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install agent-framework azure-identity python-dotenv
```

### Step 2: Configure Environment

Create a `.env` file:

```env
AZURE_OPENAI_ENDPOINT=https://oai-agents-platform.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4o
```

### Step 3: Create the Agent

Create `agent_app.py`:

```python
import asyncio
from dotenv import load_dotenv

from agent_framework import Agent
from agent_framework.openai import FoundryChatClient
from azure.identity import AzureCliCredential

load_dotenv()

async def main():
    # Create the chat client backed by Azure OpenAI
    client = FoundryChatClient(
        project_endpoint="https://oai-agents-platform.openai.azure.com/",
        model="gpt-4o",
        credential=AzureCliCredential(),
    )

    # Create the agent
    agent = Agent(
        client=client,
        name="EnterpriseTravelAgent",
        instructions="""You are an enterprise travel agent assistant.
        You help employees with:
        - Flight and hotel bookings across Europe
        - Travel policy compliance checking
        - Expense report preparation
        - Visa and documentation requirements
        Keep responses concise and professional.""",
    )

    # Non-streaming response
    result = await agent.run("What flights are available from London to Paris next week?")
    print(f"Agent: {result}")

    # Streaming response
    print("\nAgent (streaming): ", end="", flush=True)
    async for chunk in agent.run("What hotels do you recommend in Paris?", stream=True):
        if chunk.text:
            print(chunk.text, end="", flush=True)
    print()

asyncio.run(main())
```

### Step 4: Run the Agent

```bash
python agent_app.py
```

---

## Part 2: Add Agent Memory

Memory enables agents to maintain context across conversations. The Agent Framework supports multiple storage backends.

### Memory Storage Options

| Storage | Best For | Persistence | Scalability |
|---------|----------|-------------|-------------|
| **In-Memory (dict)** | Development/testing | None (lost on restart) | Single process |
| **Local File Storage** | Development, small deployments | Disk-based | Single machine |
| **Azure Cosmos DB** | Production, multi-region | Durable, replicated | Global scale |
| **Azure Blob Storage** | Production, cost-effective | Durable | High |
| **Custom/3rd-Party** | Specialized requirements | Varies | Varies |

### Step 1: Implement Local File Storage (Lab)

For this lab, we'll use local file storage. In production, use Cosmos DB or Blob Storage.

Create `memory_agent.py`:

```python
import asyncio
import json
import os
from pathlib import Path
from dotenv import load_dotenv

from agent_framework import Agent, AgentSession
from agent_framework.openai import FoundryChatClient
from azure.identity import AzureCliCredential

load_dotenv()

class LocalFileMemory:
    """Simple file-based memory for development. 
    In production, use Azure Cosmos DB or Blob Storage."""

    def __init__(self, storage_dir: str = "./agent_memory"):
        self.storage_dir = Path(storage_dir)
        self.storage_dir.mkdir(exist_ok=True)

    def _session_path(self, session_id: str) -> Path:
        # Sanitize session_id to prevent path traversal
        safe_id = "".join(c for c in session_id if c.isalnum() or c in "-_")
        return self.storage_dir / f"{safe_id}.json"

    def load_history(self, session_id: str) -> list:
        path = self._session_path(session_id)
        if path.exists():
            return json.loads(path.read_text())
        return []

    def save_history(self, session_id: str, messages: list):
        path = self._session_path(session_id)
        path.write_text(json.dumps(messages, indent=2))


async def main():
    memory = LocalFileMemory()

    client = FoundryChatClient(
        project_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        model=os.environ["AZURE_OPENAI_DEPLOYMENT_NAME"],
        credential=AzureCliCredential(),
    )

    agent = Agent(
        client=client,
        name="EnterpriseTravelAgent",
        instructions="You are an enterprise travel agent. Remember user preferences across conversations.",
    )

    # Create a session for conversation continuity
    session_id = "user-jane-doe-session-001"
    session = AgentSession(service_session_id=session_id)

    # First interaction
    result = await agent.run(
        "I prefer window seats and vegetarian meals on flights.",
        session=session,
    )
    print(f"Agent: {result}")

    # Second interaction — agent should remember preferences
    result = await agent.run(
        "Book me a flight to Paris next Tuesday.",
        session=session,
    )
    print(f"Agent: {result}")

asyncio.run(main())
```

### Production Memory Options

For production deployments, consider these patterns:

**Azure Cosmos DB** (Recommended for multi-region):
```python
# Install: pip install azure-cosmos
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

# Use Cosmos DB for durable, globally distributed memory
client = CosmosClient(
    url="https://cosmos-agents.documents.azure.com:443/",
    credential=DefaultAzureCredential(),
)
database = client.get_database_client("agent-memory")
container = database.get_container_client("conversations")
```

**Azure Blob Storage** (Cost-effective for large payloads):
```python
# Install: pip install azure-storage-blob
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential

client = BlobServiceClient(
    account_url="https://stagentsmemory.blob.core.windows.net",
    credential=DefaultAzureCredential(),
)
container = client.get_container_client("agent-sessions")
```

---

## Part 3: Create the Agent Harness

The harness provides an interactive test environment for your agent during development.

Create `harness.py`:

```python
import asyncio
import os
from dotenv import load_dotenv

from agent_framework import Agent, AgentSession
from agent_framework.openai import FoundryChatClient
from azure.identity import AzureCliCredential

load_dotenv()


async def main():
    client = FoundryChatClient(
        project_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        model=os.environ["AZURE_OPENAI_DEPLOYMENT_NAME"],
        credential=AzureCliCredential(),
    )

    agent = Agent(
        client=client,
        name="EnterpriseTravelAgent",
        instructions="""You are an enterprise travel agent assistant.
        You help employees with flight bookings, hotel reservations,
        travel policy compliance, and expense reporting.
        Always check travel policy before confirming bookings.""",
    )

    session = AgentSession(service_session_id="harness-test-session")

    print("=" * 60)
    print("Enterprise Travel Agent - Test Harness")
    print("Type 'quit' to exit, 'reset' for new session")
    print("=" * 60)

    while True:
        user_input = input("\nYou: ").strip()

        if user_input.lower() == "quit":
            break
        if user_input.lower() == "reset":
            session = AgentSession(service_session_id=f"harness-{id(session)}")
            print("[Session reset]")
            continue
        if not user_input:
            continue

        print("Agent: ", end="", flush=True)
        async for chunk in agent.run(user_input, session=session, stream=True):
            if chunk.text:
                print(chunk.text, end="", flush=True)
        print()

asyncio.run(main())
```

Run the harness:
```bash
python harness.py
```

---

## Part 4: Expose the Agent via A2A Protocol

The **Agent-to-Agent (A2A)** protocol enables standardized communication between agents built with different frameworks and technologies. Exposing your agent via A2A allows:

- **Agent Discovery** — Other agents can find your agent via its agent card
- **Message-Based Communication** — Standard protocol for sending/receiving messages
- **Long-Running Processes** — Support for async tasks via continuation tokens
- **Cross-Platform Interoperability** — Works with any A2A-compliant agent

### Step 1: Install A2A Dependencies

```bash
pip install agent-framework-a2a uvicorn starlette
```

### Step 2: Create the A2A Server

Create `a2a_server.py`:

```python
import os
import uvicorn
from dotenv import load_dotenv

from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import AgentCapabilities, AgentCard, AgentInterface, AgentSkill
from agent_framework import Agent
from agent_framework.a2a import A2AExecutor
from agent_framework.openai import FoundryChatClient
from azure.identity import AzureCliCredential
from starlette.applications import Starlette

load_dotenv()

# Define agent skills for discovery
travel_skill = AgentSkill(
    id="Travel_Booking",
    name="Travel Booking",
    description="Search and book flights and hotels across Europe.",
    tags=["flights", "hotels", "travel", "europe"],
    examples=[
        "Book a flight from London to Paris",
        "Find hotels in Berlin for next week",
    ],
)

policy_skill = AgentSkill(
    id="Policy_Check",
    name="Travel Policy Compliance",
    description="Check travel requests against company travel policy.",
    tags=["policy", "compliance", "travel"],
    examples=[
        "Is business class allowed for this trip?",
        "What is the per diem rate for Paris?",
    ],
)

# Define the public agent card — this is how other agents discover you
HOST_URL = os.getenv("A2A_HOST_URL", "http://localhost:9999")

public_agent_card = AgentCard(
    name="Enterprise Travel Agent",
    description="Helps users search and book flights and hotels across Europe. "
                "Also checks travel policy compliance and prepares expense reports.",
    version="1.0.0",
    default_input_modes=["text"],
    default_output_modes=["text"],
    capabilities=AgentCapabilities(streaming=True),
    supported_interfaces=[
        AgentInterface(url=f"{HOST_URL}/", protocol_binding="JSONRPC"),
    ],
    skills=[travel_skill, policy_skill],
)

# Create the agent
client = FoundryChatClient(
    project_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
    model=os.environ["AZURE_OPENAI_DEPLOYMENT_NAME"],
    credential=AzureCliCredential(),
)

agent = Agent(
    client=client,
    name="Enterprise Travel Agent",
    instructions="""You are a helpful Enterprise Travel Agent.
    You help with flight bookings, hotel reservations, travel policy
    compliance, and expense reporting across Europe.
    Always be professional and concise.""",
)

# Create A2A executor and request handler
request_handler = DefaultRequestHandler(
    agent_executor=A2AExecutor(agent, stream=True),
    task_store=InMemoryTaskStore(),
    agent_card=public_agent_card,
)

# Build the Starlette application
server = Starlette(
    routes=[
        *create_agent_card_routes(public_agent_card),
        *create_jsonrpc_routes(request_handler, "/"),
    ]
)

if __name__ == "__main__":
    uvicorn.run(server, host="0.0.0.0", port=9999)
```

### Step 3: Test the A2A Agent

```bash
# Start the server
python a2a_server.py
```

**Discover the agent card:**
```bash
curl http://localhost:9999/.well-known/agent.json
```

**Send a message:**
```bash
curl -X POST http://localhost:9999/v1/message:stream \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "kind": "message",
      "role": "user",
      "parts": [
        {
          "kind": "text",
          "text": "What flights are available from London to Paris?"
        }
      ],
      "messageId": null,
      "contextId": "test-session-1"
    }
  }'
```

### Step 4: Connect to the A2A Agent from Another Agent

```python
import asyncio
import httpx
from a2a.client import A2ACardResolver
from agent_framework.a2a import A2AAgent

async def main():
    a2a_host = "http://localhost:9999"

    # 1. Discover the remote agent's capabilities
    async with httpx.AsyncClient(timeout=60.0) as http_client:
        resolver = A2ACardResolver(httpx_client=http_client, base_url=a2a_host)
        agent_card = await resolver.get_agent_card()
        print(f"Found agent: {agent_card.name}")
        print(f"Skills: {[s.name for s in agent_card.skills]}")

    # 2. Send a message
    async with A2AAgent(
        name=agent_card.name,
        agent_card=agent_card,
        url=a2a_host,
    ) as agent:
        response = await agent.run("Book me a flight to Berlin next Monday")
        for message in response.messages:
            print(f"Response: {message.text}")

    # 3. Streaming responses
    async with A2AAgent(name="remote", url=a2a_host) as agent:
        stream = agent.run("Tell me about visa requirements for France", stream=True)
        async for update in stream:
            for content in update.contents:
                if content.text:
                    print(content.text, end="", flush=True)
        print()

asyncio.run(main())
```

---

## Part 5: Deploy to Azure App Service

### Step 1: Prepare for Deployment

Create `requirements.txt`:
```
agent-framework
agent-framework-a2a
azure-identity
python-dotenv
uvicorn
starlette
a2a-sdk
```

Create `startup.sh`:
```bash
#!/bin/bash
uvicorn a2a_server:server --host 0.0.0.0 --port 8000
```

### Step 2: Deploy to App Service

```bash
# Use the App Service from Chapter 01's VNet
APP_NAME="app-travel-agent"

az webapp create \
  --resource-group $RESOURCE_GROUP \
  --plan "asp-agents-api" \
  --name $APP_NAME \
  --runtime "PYTHON:3.11" \
  --startup-file "startup.sh"

# Configure environment variables
az webapp config appsettings set \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --settings \
    AZURE_OPENAI_ENDPOINT="https://oai-agents-platform.openai.azure.com/" \
    AZURE_OPENAI_DEPLOYMENT_NAME="gpt-4o" \
    A2A_HOST_URL="https://$APP_NAME.azurewebsites.net"

# Enable managed identity
az webapp identity assign \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME

# Grant access to Azure OpenAI
WEBAPP_PRINCIPAL_ID=$(az webapp identity show \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --query principalId -o tsv)

az role assignment create \
  --assignee $WEBAPP_PRINCIPAL_ID \
  --role "Cognitive Services OpenAI User" \
  --scope $OPENAI_RESOURCE_ID

# Deploy the code
az webapp deploy \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --src-path ./enterprise-travel-agent.zip \
  --type zip
```

### Optional: Deploy to Azure Container Apps

```bash
# Create Container Apps Environment
az containerapp env create \
  --resource-group $RESOURCE_GROUP \
  --name "cae-agents" \
  --location $LOCATION \
  --infrastructure-subnet-resource-id "/subscriptions/<SUB_ID>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$VNET_NAME/subnets/snet-aca"

# Build and push container
az acr create --resource-group $RESOURCE_GROUP --name acragentsplatform --sku Premium
az acr build --registry acragentsplatform --image travel-agent:v1 .

# Deploy
az containerapp create \
  --resource-group $RESOURCE_GROUP \
  --name "ca-travel-agent" \
  --environment "cae-agents" \
  --image "acragentsplatform.azurecr.io/travel-agent:v1" \
  --target-port 8000 \
  --ingress external \
  --env-vars \
    AZURE_OPENAI_ENDPOINT="https://oai-agents-platform.openai.azure.com/" \
    AZURE_OPENAI_DEPLOYMENT_NAME="gpt-4o"
```

---

## Part 6: Register Agent in AI Gateway

Now register the deployed A2A agent in the APIM AI Gateway from Chapter 01:

1. In APIM → **APIs** → **+ Add API** → **A2A Agent API**
2. Enter the agent card URL: `https://app-travel-agent.azurewebsites.net/.well-known/agent.json`
3. APIM imports the agent metadata and creates API operations
4. Apply governance policies (rate limiting, authentication)

The agent is now governed through the central AI Gateway.

---

## Summary

| Component | Status |
|-----------|--------|
| Enterprise Travel Agent created | ✅ |
| Local file memory configured | ✅ |
| Interactive test harness working | ✅ |
| Agent exposed via A2A protocol | ✅ |
| Deployed to Azure App Service | ✅ |
| Registered in AI Gateway (APIM) | ✅ |

---

## References

- [Your First Agent](https://learn.microsoft.com/en-us/agent-framework/get-started/your-first-agent?pivots=programming-language-python)
- [Agent Memory](https://learn.microsoft.com/en-us/agent-framework/get-started/memory?pivots=programming-language-python)
- [Agent Storage Options](https://learn.microsoft.com/en-us/agent-framework/agents/conversations/storage?pivots=programming-language-python)
- [Agent Harness](https://learn.microsoft.com/en-us/agent-framework/get-started/harness?pivots=programming-language-python)
- [A2A Integration](https://learn.microsoft.com/en-us/agent-framework/integrations/a2a?pivots=programming-language-python)

---

## Next Steps

Proceed to [Chapter 03 — Create Azure API Center](./03-api-center.md)
