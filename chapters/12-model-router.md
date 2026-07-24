# Chapter 12 — Configure Model Router

## Objective

Configure **Model Router** in Azure AI Foundry to intelligently route agent requests across multiple LLMs — balancing cost, quality, and latency without changing application code.

---

## Architecture Context: Intelligent Multi-Model Orchestration

### Where This Fits

Model Router sits between the AI Gateway (APIM) and the model endpoints, making **real-time routing decisions** for every prompt. It uses a trained language model to analyze incoming requests and route them to the most appropriate LLM.

### What You Will Achieve

- Multiple model deployments (GPT-4o, GPT-4.1, o3, Claude) behind a **single endpoint**
- Routing modes: **Balanced** (default), **Quality** (best model), **Cost** (cheapest adequate model)
- **APIM policy integration** for per-consumer routing preferences
- Cost tracking that shows savings from intelligent routing

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Cost Optimization** | Simple queries route to cheaper models; complex ones to premium models — automatic savings |
| **Quality Assurance** | Critical workloads can force routing to the highest-quality model available |
| **Zero Code Changes** | Routing happens transparently — application code always calls the same endpoint |
| **Multi-Provider** | Route across Azure OpenAI, Anthropic, AWS Bedrock, and Google Gemini from one endpoint |
| **Data-Driven Decisions** | Monitor which models handle which request types for continuous optimization |

---

## Prerequisites

- Chapters 01-11 completed
- Foundry project with model deployments
- At least two model deployments (e.g., GPT-4o and GPT-4o-mini)

---

## Part 1: Understanding Model Router

### What Is Model Router?

Model Router is an intelligent traffic routing system that dynamically selects the best model for each request. It evaluates the complexity and requirements of each prompt, then routes to the optimal model.

### API Version

Model Router requires API version **2025-11-18** or later.

### Routing Modes

| Mode | Behavior | Best For |
|------|----------|----------|
| **Balanced** | Optimizes for a balance of cost and quality | Production workloads |
| **Quality** | Prefers higher-capability models | Complex reasoning tasks |
| **Cost** | Prefers lower-cost models when quality is sufficient | High-volume, simpler tasks |

### Supported Models

Model Router works with these model families:
- **GPT-5.x** (o3, o4-mini, GPT-4.1)
- **Claude** (Claude Sonnet 4)
- **DeepSeek** (DeepSeek-R1)
- **Grok** (Grok 3, Grok 3 Mini)

### Key Features

| Feature | Description |
|---------|-------------|
| **Automatic Failover** | If the selected model is unavailable, Router automatically fails over to an alternative |
| **Prompt Caching** | Router leverages prompt caching where available to reduce costs |
| **No Code Changes** | Switch between routing modes without changing application code |
| **Transparent** | Response headers indicate which model handled the request |

---

## Part 2: Deploy Model Router

### Step 1: Deploy Multiple Models

Ensure you have multiple models deployed in your Foundry project:

```bash
FOUNDRY_NAME="foundry-agents-platform"

# Deploy GPT-4o (high quality)
az cognitiveservices account deployment create \
  --resource-group $RESOURCE_GROUP \
  --name $FOUNDRY_NAME \
  --deployment-name "gpt-4o" \
  --model-name "gpt-4o" \
  --model-version "2024-11-20" \
  --model-format OpenAI \
  --sku-name GlobalStandard \
  --sku-capacity 30

# Deploy GPT-4o-mini (cost efficient)
az cognitiveservices account deployment create \
  --resource-group $RESOURCE_GROUP \
  --name $FOUNDRY_NAME \
  --deployment-name "gpt-4o-mini" \
  --model-name "gpt-4o-mini" \
  --model-version "2024-07-18" \
  --model-format OpenAI \
  --sku-name GlobalStandard \
  --sku-capacity 50

# Deploy o3 (advanced reasoning)
az cognitiveservices account deployment create \
  --resource-group $RESOURCE_GROUP \
  --name $FOUNDRY_NAME \
  --deployment-name "o3" \
  --model-name "o3" \
  --model-version "2025-04-16" \
  --model-format OpenAI \
  --sku-name GlobalStandard \
  --sku-capacity 10
```

### Step 2: Create Model Router Deployment

```bash
# Create the Model Router deployment
az cognitiveservices account deployment create \
  --resource-group $RESOURCE_GROUP \
  --name $FOUNDRY_NAME \
  --deployment-name "model-router" \
  --model-name "model-router" \
  --model-version "2025-11-18" \
  --model-format OpenAI \
  --sku-name GlobalStandard \
  --sku-capacity 50
```

---

## Part 3: Use Model Router in Code

### Step 1: Basic Usage

```python
import os
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

credential = DefaultAzureCredential()
token_provider = get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")

client = AzureOpenAI(
    azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
    azure_ad_token_provider=token_provider,
    api_version="2025-11-18",  # Required for Model Router
)

# Use the model-router deployment name
response = client.chat.completions.create(
    model="model-router",  # Points to Model Router
    messages=[
        {"role": "system", "content": "You are an enterprise policy advisor."},
        {"role": "user", "content": "What is the maximum hotel rate for international travel?"},
    ],
)

print(response.choices[0].message.content)

# Check which model actually handled the request
print(f"Model used: {response.model}")
```

### Step 2: Specify Routing Mode

```python
# Balanced mode (default) - optimizes cost vs quality
response_balanced = client.chat.completions.create(
    model="model-router",
    messages=[{"role": "user", "content": "Summarize our travel policy"}],
    extra_body={"routing_mode": "balanced"},
)
print(f"Balanced → Model: {response_balanced.model}")

# Quality mode - prefers best model
response_quality = client.chat.completions.create(
    model="model-router",
    messages=[{"role": "user", "content": "Analyze this complex multi-jurisdictional compliance scenario..."}],
    extra_body={"routing_mode": "quality"},
)
print(f"Quality → Model: {response_quality.model}")

# Cost mode - prefers cheapest adequate model
response_cost = client.chat.completions.create(
    model="model-router",
    messages=[{"role": "user", "content": "What day is it today?"}],
    extra_body={"routing_mode": "cost"},
)
print(f"Cost → Model: {response_cost.model}")
```

---

## Part 4: Configure Model Router in APIM

### Update the AI Gateway Policy

Add Model Router awareness to your APIM policy from Chapter 02:

```xml
<policies>
  <inbound>
    <base />
    <!-- Route through Model Router by default -->
    <set-backend-service
      base-url="https://foundry-agents-platform.openai.azure.com/openai" />
    
    <!-- Override deployment based on routing mode header -->
    <choose>
      <when condition="@(context.Request.Headers.GetValueOrDefault("X-Routing-Mode", "balanced") == "quality")">
        <set-header name="X-Model-Router-Mode" exists-action="override">
          <value>quality</value>
        </set-header>
      </when>
      <when condition="@(context.Request.Headers.GetValueOrDefault("X-Routing-Mode", "balanced") == "cost")">
        <set-header name="X-Model-Router-Mode" exists-action="override">
          <value>cost</value>
        </set-header>
      </when>
    </choose>
    
    <!-- Log routing decisions -->
    <trace source="ModelRouter"
           severity="information">
      <message>@($"Routing mode: {context.Request.Headers.GetValueOrDefault("X-Routing-Mode", "balanced")}")</message>
    </trace>
  </inbound>
  <outbound>
    <base />
    <!-- Log which model was used -->
    <trace source="ModelRouter"
           severity="information">
      <message>@($"Model selected: {context.Response.Headers.GetValueOrDefault("x-model-used", "unknown")}")</message>
    </trace>
  </outbound>
</policies>
```

---

## Part 5: Update Agents to Use Model Router

### Update Agent Framework Agent

```python
from agent_framework import Agent, FoundryChatClient

# Point the agent to Model Router instead of a specific model
chat_client = FoundryChatClient(
    endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
    model="model-router",  # Model Router handles selection
    api_version="2025-11-18",
)

travel_agent = Agent(
    name="TravelAgent",
    instructions="You are an enterprise travel agent...",
    chat_client=chat_client,
)
```

### Update Prompt Agent

```python
# Update the Prompt Agent to use Model Router
agent = project_client.agents.create_version(
    agent_name="EnterprisePolicyAdvisorRouted",
    definition=PromptAgentDefinition(
        model="model-router",  # Use Model Router
        instructions="...",
        tools=[knowledge_tool, mcp_tool, work_iq_tool],
    ),
)
```

---

## Part 6: Monitor Routing Decisions

### Application Insights Query

Use the following KQL query to analyze Model Router decisions:

```kql
// Model Router routing analysis
customEvents
| where name == "ModelRouterDecision"
| extend modelUsed = tostring(customDimensions.model_used)
| extend routingMode = tostring(customDimensions.routing_mode)
| extend latencyMs = todouble(customDimensions.latency_ms)
| extend tokenCost = todouble(customDimensions.estimated_cost)
| summarize
    RequestCount = count(),
    AvgLatency = avg(latencyMs),
    TotalCost = sum(tokenCost)
  by modelUsed, routingMode, bin(timestamp, 1h)
| order by timestamp desc
```

### Cost Comparison Dashboard

Track cost savings with Model Router:

| Metric | Without Router | With Router (Balanced) |
|--------|---------------|----------------------|
| Average cost per request | $0.015 | $0.008 |
| Quality score (1-10) | 9.2 | 8.9 |
| Average latency | 2.1s | 1.8s |
| Monthly estimated cost | $4,500 | $2,400 |

---

## Summary

| Component | Status |
|-----------|--------|
| Multiple models deployed (GPT-4o, GPT-4o-mini, o3) | ✅ |
| Model Router deployment created | ✅ |
| Routing modes tested (Balanced, Quality, Cost) | ✅ |
| APIM policy updated for routing | ✅ |
| Agents updated to use Model Router | ✅ |
| Monitoring and cost tracking configured | ✅ |

---

## References

- [Model Router Overview](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/model-router)
- [Model Router How-To](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/model-router)
- [Supported Models](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/models)

---

## Next Steps

Proceed to [Chapter 13 — Build a Custom Engine Agent for M365 Copilot](./13-m365-custom-engine.md)
