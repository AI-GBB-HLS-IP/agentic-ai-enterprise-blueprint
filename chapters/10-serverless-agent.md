# Chapter 10 — Build a Serverless Agent with Azure Functions

## Objective

Build a **Serverless Agent** using the Azure Functions **Agents Runtime** — a lightweight framework where agents are defined in `.agent.md` markdown files, tools in `mcp.json`, and deployment via `azd`.

---

## Architecture Context: Event-Driven Agents at Scale

### Where This Fits

Serverless agents complement hosted agents (Chapter 08) for scenarios where **event-driven, pay-per-execution** economics make more sense than always-running containers. Ideal for agents that respond to triggers (HTTP, queue, timer) rather than maintaining persistent connections.

### What You Will Achieve

- An agent defined entirely in **markdown** (`.agent.md`) with no boilerplate code
- MCP tool connections declared in **`mcp.json`** pointing to governed tools in APIM
- **One-command deployment** via `azd up` with VNet integration
- An agent that scales to zero when idle and scales up automatically under load

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Zero Idle Cost** | Pay only when the agent is invoked — no cost when there's no traffic |
| **Markdown-First** | Define agent behavior in `.agent.md` — accessible to non-developers |
| **Instant Scale** | Azure Functions scales automatically from 0 to thousands of concurrent executions |
| **Event-Driven** | Trigger agents from queues, timers, webhooks, or Cosmos DB change feeds |
| **azd Deployment** | Single command deploys agent + infrastructure — perfect for CI/CD |

---

## Prerequisites

- Chapters 01-09 completed
- Azure Functions Core Tools v4+
- Azure Developer CLI (`azd`) installed
- Node.js 20+ or Python 3.11+

---

## Part 1: Understanding the Serverless Agents Runtime

### What Is It?

The Azure Functions Agents Runtime allows you to:
- Define agents as **markdown files** (`.agent.md`)
- Connect tools via **MCP configuration** (`mcp.json`)
- Orchestrate agents via **YAML configuration** (`agents.config.yaml`)
- Deploy with a single `azd up` command

### Key Concepts

| Concept | Description |
|---------|-------------|
| `.agent.md` | Markdown file defining an agent's instructions and behavior |
| `mcp.json` | JSON file listing MCP servers the agent can call |
| `agents.config.yaml` | YAML config mapping agents to models, tools, and triggers |
| **Function Trigger** | HTTP trigger for direct invocation, or timer/queue for scheduled agents |

---

## Part 2: Scaffold the Project

### Step 1: Initialize with azd

```bash
mkdir serverless-agents && cd serverless-agents

# Initialize from the serverless agents template
azd init --template azure-functions-agents-runtime
```

### Step 2: Project Structure

After scaffolding, your project looks like:

```
serverless-agents/
├── agents/
│   ├── expense-reviewer.agent.md     # Agent definition
│   └── policy-checker.agent.md       # Another agent
├── mcp.json                          # MCP server connections
├── agents.config.yaml                # Agent orchestration config
├── host.json                         # Azure Functions host config
├── local.settings.json               # Local environment variables
├── infra/                            # Bicep templates for azd
│   ├── main.bicep
│   └── modules/
└── azure.yaml                        # azd project definition
```

---

## Part 3: Define the Agents

### Step 1: Create the Expense Reviewer Agent

Create `agents/expense-reviewer.agent.md`:

````markdown
# Expense Reviewer Agent

You are an automated expense reviewer for the enterprise. Your job is to
review submitted expense reports and check them against company policy.

## Instructions

1. When an expense report is submitted, retrieve the relevant policy
   using the enterprise-policies knowledge tool.

2. Check each line item against policy limits:
   - Verify hotel rates don't exceed maximums ($250 domestic, $350 international)
   - Verify per diem amounts match the destination
   - Verify receipts are present for items over $25

3. For compliant reports, approve them automatically.

4. For non-compliant items, flag them with specific policy references
   and request corrections.

5. Use the HR MCP server to look up the employee's department and
   travel authorization level.

## Tools Available

- `enterprise-tools`: MCP server for HR lookups and ticket creation
- `expense-api`: MCP server for expense report operations

## Output Format

Respond with a structured review:
```json
{
  "status": "approved" | "needs_revision",
  "items_reviewed": 5,
  "flagged_items": [],
  "comments": "..."
}
```
````

### Step 2: Create the Policy Checker Agent

Create `agents/policy-checker.agent.md`:

````markdown
# Policy Checker Agent

You are a policy compliance checker. Given a proposed action (travel,
purchase, hiring, etc.), you check it against enterprise policies.

## Instructions

1. Accept a proposed action from the user.
2. Query the enterprise-policies knowledge base for relevant policies.
3. Evaluate compliance and return a clear yes/no with justification.

## Response Format

Always respond with:
- **Compliant**: Yes / No / Partial
- **Policy Reference**: Specific section and rule
- **Recommendation**: What to do if non-compliant
````

---

## Part 4: Configure MCP Connections

### Step 1: Define MCP Servers

Create `mcp.json`:

```json
{
  "servers": {
    "enterprise-tools": {
      "type": "sse",
      "url": "https://apim-agents-gateway.azure-api.net/mcp/enterprise-tools/mcp",
      "headers": {
        "Ocp-Apim-Subscription-Key": "${APIM_SUBSCRIPTION_KEY}"
      }
    },
    "expense-api": {
      "type": "sse",
      "url": "https://apim-agents-gateway.azure-api.net/mcp/expense-api/mcp",
      "headers": {
        "Ocp-Apim-Subscription-Key": "${APIM_SUBSCRIPTION_KEY}"
      }
    }
  }
}
```

### Step 2: Configure Agent Orchestration

Create `agents.config.yaml`:

```yaml
version: "1.0"
defaults:
  model:
    provider: azure_openai
    endpoint: ${AZURE_OPENAI_ENDPOINT}
    deployment: gpt-4o
    api_version: "2024-12-01-preview"

agents:
  expense-reviewer:
    file: agents/expense-reviewer.agent.md
    trigger: http
    route: api/review-expense
    tools:
      - enterprise-tools
      - expense-api

  policy-checker:
    file: agents/policy-checker.agent.md
    trigger: http
    route: api/check-policy
    tools:
      - enterprise-tools
```

---

## Part 5: Local Development and Testing

### Step 1: Configure Local Settings

Update `local.settings.json`:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "AZURE_OPENAI_ENDPOINT": "https://apim-agents-gateway.azure-api.net",
    "AZURE_OPENAI_API_KEY": "<your-apim-key>",
    "APIM_SUBSCRIPTION_KEY": "<your-subscription-key>"
  }
}
```

### Step 2: Run Locally

```bash
# Start the function app
func start
```

### Step 3: Test the Agents

```bash
# Test the expense reviewer
curl -X POST http://localhost:7071/api/review-expense \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Please review this expense report: 3 nights at Hotel Munich at $280/night, 4 taxi rides totaling $120, meals for 3 days in Germany."
  }'

# Test the policy checker
curl -X POST http://localhost:7071/api/check-policy \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Can I book a business class flight from New York to London? The flight is 7 hours."
  }'
```

---

## Part 6: Deploy to Azure

### Step 1: Configure VNet Integration

Update the Bicep infrastructure to deploy the Function App with VNet integration:

Add to `infra/modules/function-app.bicep`:

```bicep
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: appServiceSubnetId
    siteConfig: {
      appSettings: [
        { name: 'AZURE_OPENAI_ENDPOINT', value: openAiEndpoint }
        { name: 'APIM_SUBSCRIPTION_KEY', value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=apim-subscription-key)' }
      ]
      vnetRouteAllEnabled: true
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}
```

### Step 2: Deploy with azd

```bash
# Login and provision
azd auth login
azd env set AZURE_LOCATION $LOCATION
azd env set AZURE_RESOURCE_GROUP $RESOURCE_GROUP

# Provision infrastructure and deploy code
azd up
```

### Step 3: Verify Deployment

```bash
# Get the function app URL
FUNC_URL=$(az functionapp show \
  --resource-group $RESOURCE_GROUP \
  --name "func-agents-serverless" \
  --query "defaultHostName" -o tsv)

# Test the deployed expense reviewer
curl -X POST "https://$FUNC_URL/api/review-expense" \
  -H "Content-Type: application/json" \
  -d '{"message": "Review: 2 nights in Paris hotel at $340/night, economy flight $450"}'
```

---

## Part 7: Register in APIM

Register the serverless agents in API Management for unified governance:

```bash
# Import the Function App APIs into APIM
az apim api import \
  --resource-group $RESOURCE_GROUP \
  --service-name "apim-agents-gateway" \
  --api-id "serverless-agents" \
  --path "agents/serverless" \
  --display-name "Serverless Agents" \
  --service-url "https://func-agents-serverless.azurewebsites.net" \
  --specification-format OpenApi \
  --specification-url "https://func-agents-serverless.azurewebsites.net/api/openapi.json"
```

---

## Summary

| Component | Status |
|-----------|--------|
| Project scaffolded with azd template | ✅ |
| Expense Reviewer agent defined (.agent.md) | ✅ |
| Policy Checker agent defined (.agent.md) | ✅ |
| MCP connections configured (mcp.json) | ✅ |
| Agent orchestration configured (agents.config.yaml) | ✅ |
| Local testing passed | ✅ |
| Deployed to Azure with VNet integration | ✅ |
| Registered in APIM | ✅ |

---

## References

- [Serverless Agents Runtime](https://learn.microsoft.com/en-us/azure/azure-functions/scenario-serverless-agents-runtime)
- [Azure Functions Networking Options](https://learn.microsoft.com/en-us/azure/azure-functions/functions-networking-options)

---

## Next Steps

Proceed to [Chapter 11 — Create a Fabric IQ Agent (Optional)](./11-fabric-iq.md)
