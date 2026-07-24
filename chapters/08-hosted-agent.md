# Chapter 08 — Build a Hosted Agent in Foundry

## Objective

Take the Enterprise Travel Agent built with the Agent Framework (Chapter 02) and deploy it as a **Hosted Agent** in Microsoft Foundry. Hosted agents run your own container image on Azure Container Apps within Foundry's managed infrastructure.

---

## Prerequisites

- Chapters 01-07 completed
- Azure Container Registry (ACR) from Chapter 02
- Agent Framework code from Chapter 02
- Foundry with BYO VNet from Chapter 05

---

## Part 1: Understanding Hosted Agents

### Hosted vs. Prompt Agents

| Feature | Hosted Agent | Prompt Agent |
|---------|-------------|-------------|
| **Compute** | Your container on ACA (Micro VM) | Fully Microsoft-managed |
| **Control** | Custom CPU, memory, code | Configuration only |
| **Container** | Your ACR image | None |
| **NIC** | Dedicated NIC in delegated subnet | Shared data proxy |
| **IP Usage** | Revisions consume IPs | Revisions do NOT consume IPs |
| **Scaling** | Custom scaling rules | Automatic |
| **Use Case** | Complex logic, custom dependencies | Simple prompt-based agents |

### Hosted Agent Limits

- **100 active revisions** per agent
- **1,000 total revisions** per agent name
- **~200 Hosted agents** per Foundry instance
- Custom CPU/memory pairs selectable per version

---

## Part 2: Containerize the Agent

### Step 1: Create Dockerfile

Create `Dockerfile` in the `enterprise-travel-agent/` directory:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Run the A2A server
CMD ["uvicorn", "a2a_server:server", "--host", "0.0.0.0", "--port", "8000"]
```

### Step 2: Build and Push to ACR

```bash
# Build and push to ACR
az acr build \
  --registry acragentsplatform \
  --image enterprise-travel-agent:v1 \
  --file Dockerfile \
  .
```

### Step 3: Grant Foundry Access to ACR

```bash
# Get Foundry managed identity
FOUNDRY_PRINCIPAL_ID=$(az cognitiveservices account show \
  --resource-group $RESOURCE_GROUP \
  --name $FOUNDRY_NAME \
  --query "identity.principalId" -o tsv)

# Grant ACR pull access
ACR_ID=$(az acr show --name acragentsplatform --query id -o tsv)

az role assignment create \
  --assignee $FOUNDRY_PRINCIPAL_ID \
  --role "AcrPull" \
  --scope $ACR_ID
```

---

## Part 3: Deploy as Hosted Agent

### Step 1: Deploy via Python SDK

```python
import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import HostedAgentDefinition

load_dotenv()

endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"]

with (
    DefaultAzureCredential() as credential,
    AIProjectClient(endpoint=endpoint, credential=credential) as project_client,
):
    # Deploy the hosted agent
    hosted_agent = project_client.agents.create_version(
        agent_name="EnterpriseTravelAgentHosted",
        definition=HostedAgentDefinition(
            # Container configuration
            container_image="acragentsplatform.azurecr.io/enterprise-travel-agent:v1",
            container_port=8000,
            # Resource allocation
            cpu=1.0,
            memory="2Gi",
            # Scaling
            min_replicas=1,
            max_replicas=10,
            # Environment variables
            environment_variables={
                "AZURE_OPENAI_ENDPOINT": os.environ["AZURE_OPENAI_ENDPOINT"],
                "AZURE_OPENAI_DEPLOYMENT_NAME": os.environ["FOUNDRY_MODEL_NAME"],
            },
        ),
    )

    print(f"Hosted agent deployed: {hosted_agent.name}")
    print(f"Version: {hosted_agent.version}")
    print(f"Status: {hosted_agent.status}")
```

### Step 2: Deploy via Foundry Portal

Alternatively, use the Foundry Portal:

1. Navigate to your project in [Foundry Portal](https://ai.azure.com)
2. Go to **Agents** → **+ Create Agent** → **Hosted Agent**
3. Configure:
   - **Name**: `EnterpriseTravelAgentHosted`
   - **Container Registry**: `acragentsplatform`
   - **Image**: `enterprise-travel-agent:v1`
   - **Port**: `8000`
   - **CPU**: 1.0
   - **Memory**: 2 GiB
4. Add environment variables
5. Deploy

### Step 3: Verify Deployment

```python
# Check agent status
agent_status = project_client.agents.get_version(
    agent_name="EnterpriseTravelAgentHosted",
    agent_version=hosted_agent.version,
)
print(f"Status: {agent_status.status}")
print(f"Endpoint: {agent_status.endpoint}")
```

---

## Part 4: BYO VNet Considerations for Hosted Agents

### Outbound Connectivity

Each Hosted Agent runs in a **Micro VM** with a dedicated network interface in the delegated subnet:

| Traffic Type | Route |
|-------------|-------|
| Agent's own outbound traffic | Through the Micro VM's dedicated NIC |
| Tool server calls | Through the single-tenant data proxy |

### Firewall Requirements

For source-code agent deployments with BYO VNet, ensure outbound access to:

- Azure Container Registry endpoints
- Microsoft Container Registry (MCR) for base images
- Azure management APIs for provisioning

### IP Consumption During Updates

When you deploy a new version:
1. A new revision is created
2. Old and new revisions run **in parallel** during traffic shift
3. Both consume IPs from the delegated subnet
4. Old revision scales down after traffic migration

> **Tip**: Monitor your subnet utilization during deployments. Use a /24 subnet to have buffer.

---

## Part 5: Test the Hosted Agent

### Invoke via A2A

The hosted agent exposes the same A2A interface as when running on App Service:

```python
import httpx
from a2a.client import A2ACardResolver
from agent_framework.a2a import A2AAgent

async def test_hosted_agent():
    hosted_url = "https://foundry-agents-platform.services.ai.azure.com/agents/EnterpriseTravelAgentHosted"

    async with A2AAgent(name="travel-hosted", url=hosted_url) as agent:
        response = await agent.run("Find flights from London to Berlin next week")
        for message in response.messages:
            print(f"Response: {message.text}")
```

### Invoke via Foundry SDK

```python
# Use the Foundry SDK to invoke
openai_client = project_client.get_openai_client()

response = openai_client.responses.create(
    input="I need to book a hotel in Munich for 3 nights",
    extra_body={
        "agent_reference": {
            "name": "EnterpriseTravelAgentHosted",
            "type": "agent_reference",
        }
    },
)
print(response.output_text)
```

---

## Summary

| Component | Status |
|-----------|--------|
| Agent containerized with Dockerfile | ✅ |
| Container pushed to ACR | ✅ |
| Hosted agent deployed in Foundry | ✅ |
| BYO VNet connectivity verified | ✅ |
| A2A endpoint accessible | ✅ |

---

## References

- [Deploy Hosted Agent Code](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-code?tabs=python)
- [Hosted Agent Networking](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive#hosted-agents-networking-behavior)

---

## Next Steps

Proceed to [Chapter 09 — Connect Your Agent with Work IQ](./09-work-iq.md)
