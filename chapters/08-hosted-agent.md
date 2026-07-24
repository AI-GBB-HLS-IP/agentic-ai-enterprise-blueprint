# Chapter 08 — Build a Hosted Agent in Foundry

## Objective

Take the Enterprise Travel Agent built with the Agent Framework (Chapter 03) and deploy it as a **Hosted Agent** in Microsoft Foundry. Hosted agents run your own container image on Azure Container Apps within Foundry's managed infrastructure.

---

## Architecture Context: Production-Grade Agent Deployment

### Where This Fits

Hosted Agents bridge the gap between **development** (Chapter 03) and **production**. You bring your own container image with full control over the runtime, while Foundry handles scaling, networking, and lifecycle management within your VNet.

### What You Will Achieve

- Your Agent Framework agent **containerized** with a production-ready Dockerfile
- The container deployed as a **Hosted Agent** in Foundry with BYO VNet integration
- The hosted agent accessible via **A2A protocol** and **SDK** for testing
- The hosted agent **exposed via A2A in APIM** for enterprise-wide consumption with governance

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Full Runtime Control** | Bring any Python/Node.js runtime, custom dependencies, or proprietary libraries |
| **Managed Scaling** | Foundry auto-scales your container based on request load — no manual intervention |
| **VNet Integration** | Your agent runs inside your delegated subnet with full private network access |
| **Enterprise Governance** | Exposing via APIM means rate limiting, auth, monitoring, and policy apply automatically |
| **A2A Interoperability** | Other agents across the platform can discover and invoke your hosted agent seamlessly |

---

## Prerequisites

- Chapters 01-07 completed
- Azure Container Registry (ACR) from Chapter 03
- Agent Framework code from Chapter 03
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

## Part 6: Expose Hosted Agent via A2A in APIM

Now that your hosted agent is running in Foundry, you need to **expose it through the AI Gateway (APIM)** so that:
- Other agents across the enterprise can discover and invoke it with full governance
- Rate limiting, authentication, and monitoring apply to all inbound A2A requests
- The agent is registered in the enterprise catalog for discoverability

### Step 1: Create the A2A API Definition

Create an OpenAPI spec for the hosted agent's A2A endpoint:

```yaml
# hosted-travel-agent-a2a.yaml
openapi: 3.0.1
info:
  title: Enterprise Travel Agent (Hosted) - A2A
  description: A2A interface for the hosted travel agent in Foundry
  version: "1.0"
servers:
  - url: https://foundry-agents-platform.services.ai.azure.com
paths:
  /agents/EnterpriseTravelAgentHosted/.well-known/agent.json:
    get:
      operationId: getAgentCard
      summary: Get Agent Card
      responses:
        '200':
          description: Agent Card
  /agents/EnterpriseTravelAgentHosted/a2a:
    post:
      operationId: invokeAgent
      summary: Invoke agent via A2A protocol
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                jsonrpc:
                  type: string
                method:
                  type: string
                params:
                  type: object
      responses:
        '200':
          description: A2A response
```

### Step 2: Import into APIM

```bash
# Import the A2A API into APIM
az apim api import \
  --resource-group rg-internet-of-agents \
  --service-name apim-agents-gateway \
  --api-id hosted-travel-agent-a2a \
  --path "agents/travel" \
  --specification-format OpenApi \
  --specification-path ./hosted-travel-agent-a2a.yaml \
  --display-name "Enterprise Travel Agent (Hosted)" \
  --service-url "https://foundry-agents-platform.services.ai.azure.com" \
  --protocols https \
  --subscription-required true
```

### Step 3: Apply A2A Governance Policy

```xml
<policies>
  <inbound>
    <base />
    <!-- Validate JWT for A2A callers -->
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
      <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
      <required-claims>
        <claim name="aud" match="all">
          <value>{your-foundry-app-id}</value>
        </claim>
      </required-claims>
    </validate-jwt>
    <!-- Rate limit A2A calls -->
    <rate-limit-by-key calls="100" renewal-period="60"
      counter-key="@(context.Request.Headers.GetValueOrDefault("X-Agent-Id","anonymous"))" />
    <!-- Log for observability -->
    <set-header name="X-Request-Source" exists-action="override">
      <value>@(context.Request.Headers.GetValueOrDefault("X-Agent-Id","unknown"))</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
</policies>
```

### Step 4: Register in API Center

```bash
# Register the A2A endpoint in API Center for discoverability
az apic api register \
  --resource-group rg-internet-of-agents \
  --service-name apic-agents-platform \
  --api-id "hosted-travel-agent" \
  --title "Enterprise Travel Agent (Hosted)" \
  --type "a2a" \
  --description "A hosted agent for travel planning — flights, hotels, itineraries" \
  --custom-properties '{"agentType": "hosted", "iqLayers": ["foundry-iq"], "mcpTools": ["flight-search", "hotel-booking"]}'
```

### Step 5: Verify End-to-End

```python
import httpx

# Other agents now invoke the hosted agent through APIM (governed)
async def invoke_via_apim():
    apim_url = "https://apim-agents-gateway.azure-api.net/agents/travel/a2a"

    headers = {
        "Authorization": f"Bearer {get_agent_token()}",
        "X-Agent-Id": "customer-success-agent",
        "Ocp-Apim-Subscription-Key": "{subscription-key}"
    }

    payload = {
        "jsonrpc": "2.0",
        "method": "tasks/send",
        "params": {
            "id": "task-001",
            "message": {
                "role": "user",
                "parts": [{"type": "text", "text": "Find flights from NYC to London next Monday"}]
            }
        }
    }

    async with httpx.AsyncClient() as client:
        response = await client.post(apim_url, json=payload, headers=headers)
        print(response.json())
```

Now any agent in the enterprise can discover and invoke your hosted travel agent through the governed AI Gateway — with full rate limiting, authentication, monitoring, and cost attribution.

---

## Summary

| Component | Status |
|-----------|--------|
| Agent containerized with Dockerfile | ✅ |
| Container pushed to ACR | ✅ |
| Hosted agent deployed in Foundry | ✅ |
| BYO VNet connectivity verified | ✅ |
| A2A endpoint accessible | ✅ |
| Exposed via A2A in APIM | ✅ |
| Registered in API Center | ✅ |

---

## References

- [Deploy Hosted Agent Code](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-code?tabs=python)
- [Hosted Agent Networking](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive#hosted-agents-networking-behavior)
- [Import A2A APIs into APIM](https://learn.microsoft.com/en-us/azure/api-management/import-api-from-oas)

---

## Next Steps

Proceed to [Chapter 09 — Connect Your Agent with Work IQ](./09-work-iq.md)
