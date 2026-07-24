# Chapter 09 — Connect Your Agent with Work IQ

## Objective

Connect your Foundry agent to **Work IQ** to enable it to query Microsoft 365 data — emails, calendar events, Teams messages, files, and contacts — on behalf of the user.

---

## Prerequisites

- Chapters 01-08 completed
- Microsoft 365 tenant with user mailboxes
- Microsoft Entra ID admin permissions for app registration
- Users with Exchange Online licenses

---

## Part 1: Understanding Work IQ

### What Is Work IQ?

Work IQ connects Foundry agents to the Microsoft 365 productivity graph. When enabled, an agent can:

- **Search emails** (Outlook)
- **Read calendar events** (Exchange)
- **Find files** (OneDrive, SharePoint)
- **Access people information** (Microsoft Graph People API)
- **Read Teams messages** (Microsoft Teams)

### How It Works

Work IQ operates via **On-Behalf-Of (OBO)** authentication:

```
User → Foundry Agent → Work IQ → Microsoft Graph → M365 Data
        (uses OBO token)
```

1. User authenticates with Entra ID
2. Agent obtains an OBO token via the Foundry platform
3. Work IQ uses the OBO token to call Microsoft Graph
4. Results returned to the agent with the user's permissions
5. Agent can only access data the **signed-in user** already has access to

### Critical BYO VNet Limitation

> **⚠️ Work IQ does NOT support VNet integration.**
>
> Virtual network (VNet) integration is not supported for Work IQ. If your Foundry project uses BYO networking, Work IQ traffic will route through Microsoft's managed network to reach Microsoft Graph APIs, not through your VNet.

**Impact**: This means Work IQ calls traverse the public internet (encrypted with TLS), not your private network. For most enterprises, this is acceptable because:
- All traffic uses TLS 1.2+ encryption
- Microsoft Graph APIs are already public endpoints
- OBO tokens are short-lived and scoped to the user's permissions
- No enterprise data is persisted by Work IQ

**If this is not acceptable**: Skip Work IQ and build a custom Microsoft Graph integration using the Azure Functions serverless agent (Chapter 10) with private endpoints.

---

## Part 2: Register the Entra ID Application

### Step 1: Create App Registration

```bash
# Create the app registration
APP_NAME="WorkIQ-AgentsPlatform"

APP_ID=$(az ad app create \
  --display-name $APP_NAME \
  --web-redirect-uris "https://foundry-agents-platform.services.ai.azure.com/auth/callback" \
  --required-resource-accesses '[{
    "resourceAppId": "00000003-0000-0000-c000-000000000000",
    "resourceAccess": [
      { "id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d", "type": "Scope" },
      { "id": "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0", "type": "Scope" },
      { "id": "7427e0e9-2fba-42fe-b0c0-848c9e6a8182", "type": "Scope" },
      { "id": "14dad69e-099b-42c9-810b-d002981feec1", "type": "Scope" },
      { "id": "465a38f9-76ea-45b9-9f34-9e8b0d4b0b42", "type": "Scope" },
      { "id": "ff74d97f-43af-4b68-9f2a-b77988d0c39f", "type": "Scope" }
    ]
  }]' \
  --query appId -o tsv)

echo "App ID: $APP_ID"
```

The permissions correspond to:

| Permission ID | Permission | Description |
|--------------|------------|-------------|
| `e1fe6dd8-...` | `User.Read` | Sign in and read user profile |
| `64a6cdd6-...` | `Email.Read` | Read user mail |
| `7427e0e9-...` | `Calendars.Read` | Read user calendars |
| `14dad69e-...` | `profile` | View users' basic profile |
| `465a38f9-...` | `People.Read` | Read users' relevant people lists |
| `ff74d97f-...` | `Sites.Read.All` | Read items in all site collections |

### Step 2: Add the Work IQ API Permission

Work IQ requires a specific delegated permission: `WorkIQAgent.Ask`

```bash
# Find the Work IQ API's service principal
WORKIQ_SP=$(az ad sp list \
  --display-name "Work IQ Agent API" \
  --query "[0].appId" -o tsv)

# If not found, look for the known resource app ID
# The Work IQ API app ID is published in Microsoft documentation

# Add the WorkIQAgent.Ask permission to your app
az ad app permission add \
  --id $APP_ID \
  --api $WORKIQ_SP \
  --api-permissions "<WorkIQAgent.Ask-permission-id>=Scope"
```

### Step 3: Grant Admin Consent

```bash
# Grant admin consent for all configured permissions
az ad app permission admin-consent --id $APP_ID
```

### Step 4: Create Client Secret

```bash
# Create a client secret
CLIENT_SECRET=$(az ad app credential reset \
  --id $APP_ID \
  --append \
  --display-name "WorkIQ-Secret" \
  --years 1 \
  --query password -o tsv)

echo "Client Secret: $CLIENT_SECRET"
```

> **Security**: Store the client secret in Azure Key Vault immediately:

```bash
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "workiq-client-secret" \
  --value "$CLIENT_SECRET"
```

---

## Part 3: Configure Work IQ in Foundry

### Step 1: Enable Work IQ Connection

1. Navigate to your Foundry project in [Foundry Portal](https://ai.azure.com)
2. Go to **Settings** → **Connections** → **+ New Connection**
3. Select **Work IQ** or **Microsoft 365**
4. Configure:
   - **Application (client) ID**: `$APP_ID`
   - **Client Secret**: (from Key Vault)
   - **Tenant ID**: Your Entra tenant ID
5. Test the connection

### Step 2: Add Work IQ Tool to Agent

```python
import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    PromptAgentDefinition,
    FoundryIQTool,
    McpTool,
    WorkIQTool,
)

load_dotenv()

endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"]
model = os.environ["FOUNDRY_MODEL_NAME"]

with (
    DefaultAzureCredential() as credential,
    AIProjectClient(endpoint=endpoint, credential=credential) as project_client,
):
    # All tools including Work IQ
    knowledge_tool = FoundryIQTool(
        index_name="enterprise-policies",
        description="Search enterprise travel and expense policies",
    )

    mcp_tool = McpTool(
        server_url="https://apim-agents-gateway.azure-api.net/mcp/enterprise-tools/mcp",
        server_label="Enterprise Tools",
        connection_id="<apim-connection-id>",
    )

    work_iq_tool = WorkIQTool(
        connection_id="<work-iq-connection-id>",
        description="Search user's Microsoft 365 data including emails, calendar, files, and contacts",
    )

    # Create agent with Work IQ
    agent = project_client.agents.create_version(
        agent_name="EnterprisePolicyAdvisorWithM365",
        definition=PromptAgentDefinition(
            model=model,
            instructions="""You are an Enterprise Policy Advisor with M365 access.

Your capabilities:
1. **Policy Lookup**: Search enterprise policies via Foundry IQ.
2. **Employee Tools**: Use MCP tools via APIM for HR/IT operations.
3. **M365 Access** (via Work IQ): Search the user's emails, calendar, 
   files, and contacts to provide contextual assistance.
4. **Travel Delegation**: Delegate bookings to the Travel Agent via A2A.

When a user asks about travel:
- Check their calendar for conflicting events
- Search their email for any related travel approvals
- Look up the relevant policy
- Coordinate the booking through the Travel Agent

Important: You can only access M365 data that the signed-in user 
already has permission to view. Never assume access to data outside 
the user's permission scope.""",
            tools=[knowledge_tool, mcp_tool, work_iq_tool],
        ),
    )
    print(f"Agent with Work IQ created: {agent.name}")
```

---

## Part 4: Test Work IQ Integration

```python
# Test 1: Calendar awareness
response = openai_client.responses.create(
    input="Do I have any conflicts next Tuesday? I'm planning a trip to Berlin.",
    extra_body={
        "agent_reference": {
            "name": "EnterprisePolicyAdvisorWithM365",
            "type": "agent_reference",
        }
    },
)
print(f"Calendar Check:\n{response.output_text}\n")

# Test 2: Email context
response = openai_client.responses.create(
    input="Check if my manager has approved my travel request for the Munich conference",
    extra_body={
        "agent_reference": {
            "name": "EnterprisePolicyAdvisorWithM365",
            "type": "agent_reference",
        }
    },
)
print(f"Email Search:\n{response.output_text}\n")

# Test 3: File search
response = openai_client.responses.create(
    input="Find the latest travel expense template in my OneDrive",
    extra_body={
        "agent_reference": {
            "name": "EnterprisePolicyAdvisorWithM365",
            "type": "agent_reference",
        }
    },
)
print(f"File Search:\n{response.output_text}\n")
```

---

## Part 5: Security Considerations

### OBO Token Scope

- Work IQ tokens are scoped to the **delegated permissions** of the signed-in user
- The agent cannot access data the user doesn't have access to
- Tokens are short-lived and not persisted

### Conditional Access

- If your tenant uses Conditional Access policies, they apply to Work IQ calls
- MFA requirements are enforced at the user's initial sign-in
- Location-based policies apply to the Foundry endpoint, not the agent's location

### Audit Logging

Work IQ calls are logged in:
- Microsoft Entra ID sign-in logs (authentication)
- Microsoft 365 audit logs (data access)
- Foundry agent traces (tool invocations)

### Network Isolation Alternative

If the VNet limitation is unacceptable:
1. Skip Work IQ entirely
2. Build a custom Microsoft Graph connector as an Azure Function (Chapter 10)
3. Deploy the Function in your VNet with private endpoints
4. Register it as an MCP server in APIM (Chapter 01)
5. Call it from your agent like any other MCP tool

---

## Summary

| Component | Status |
|-----------|--------|
| Entra ID app registration with M365 permissions | ✅ |
| WorkIQAgent.Ask permission configured | ✅ |
| Admin consent granted | ✅ |
| Work IQ connection in Foundry | ✅ |
| Agent updated with Work IQ tool | ✅ |
| BYO VNet limitation documented | ⚠️ |
| Calendar, email, and file search tested | ✅ |

---

## References

- [Work IQ Overview](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/work-iq/overview)
- [Work IQ Connect Setup](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/work-iq/connect)
- [Microsoft Graph Permissions Reference](https://learn.microsoft.com/en-us/graph/permissions-reference)

---

## Next Steps

Proceed to [Chapter 10 — Build a Serverless Agent with Azure Functions](./10-serverless-agent.md)
