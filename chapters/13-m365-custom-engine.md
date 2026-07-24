# Chapter 13 — Build a Custom Engine Agent for M365 Copilot

## Objective

Create a **Custom Engine Agent** that extends Microsoft 365 Copilot with your enterprise agents. This enables users to invoke your Internet of Agents platform directly from Teams, Outlook, and other M365 surfaces.

---

## Prerequisites

- Chapters 01-12 completed
- Microsoft 365 E3/E5 or Microsoft 365 Copilot license
- Microsoft Teams Developer Portal access
- Node.js 20+
- Teams Toolkit for VS Code or Microsoft 365 Agents Toolkit

---

## Part 1: Understanding Custom Engine Agents

### What Is a Custom Engine Agent?

A Custom Engine Agent brings your own AI orchestration engine into M365 Copilot. Unlike Declarative Agents (which use Microsoft's orchestration), Custom Engine Agents use:
- Your own LLM (via Foundry)
- Your own tools (via APIM/MCP)
- Your own orchestration logic (Agent Framework)

### Integration Methods

| Method | Description | Best For |
|--------|-------------|----------|
| **Microsoft Agents SDK** | Build a bot with Agents SDK, Teams channel | Full control, existing bot infra |
| **Foundry Integration** | Connect Hosted Agent directly to M365 | Foundry-native agents |

### App Manifest Requirement

Custom Engine Agents require **app manifest v1.21+** with the `customEngineAgent` capability.

---

## Part 2: Scaffold the Custom Engine Agent

### Step 1: Create the Project

Using Microsoft 365 Agents Toolkit in VS Code:

1. Open VS Code → Command Palette → **Teams: Create a New App**
2. Select **Custom Engine Agent**
3. Select **AI Agent** template
4. Configure:
   - **Name**: `Enterprise Travel Copilot`
   - **Language**: TypeScript
   - **AI Service**: Azure OpenAI (via APIM)

### Step 2: Project Structure

```
enterprise-travel-copilot/
├── appPackage/
│   ├── manifest.json          # M365 app manifest (v1.21+)
│   ├── color.png
│   └── outline.png
├── src/
│   ├── index.ts               # Bot entry point
│   ├── adapter.ts             # Bot Framework adapter
│   ├── agent.ts               # Custom engine agent logic
│   └── config.ts              # Configuration
├── infra/                     # Bicep for Azure deployment
├── env/
│   ├── .env.dev               # Dev environment
│   └── .env.prod              # Production environment
├── teamsapp.yml               # Teams Toolkit lifecycle
└── package.json
```

---

## Part 3: Configure the App Manifest

### Step 1: Update manifest.json

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/teams/v1.21/MicrosoftTeams.schema.json",
  "manifestVersion": "1.21",
  "version": "1.0.0",
  "id": "{{APP_ID}}",
  "developer": {
    "name": "Enterprise Platform Team",
    "websiteUrl": "https://www.contoso.com",
    "privacyUrl": "https://www.contoso.com/privacy",
    "termsOfUseUrl": "https://www.contoso.com/terms"
  },
  "name": {
    "short": "Travel Advisor",
    "full": "Enterprise Travel Policy Advisor"
  },
  "description": {
    "short": "AI-powered travel policy advisor",
    "full": "Ask questions about travel policies, check compliance, book travel, and manage expense reports — all powered by the enterprise AI platform."
  },
  "icons": {
    "color": "color.png",
    "outline": "outline.png"
  },
  "accentColor": "#0078D4",
  "bots": [
    {
      "botId": "{{BOT_ID}}",
      "scopes": ["personal", "team", "groupChat"],
      "supportsFiles": false,
      "isNotificationOnly": false,
      "commandLists": [
        {
          "scopes": ["personal"],
          "commands": [
            { "title": "check-policy", "description": "Check travel policy compliance" },
            { "title": "review-expense", "description": "Review an expense report" },
            { "title": "book-travel", "description": "Start a travel booking" }
          ]
        }
      ]
    }
  ],
  "validDomains": [
    "{{BOT_DOMAIN}}"
  ]
}
```

---

## Part 4: Implement the Custom Engine Agent

### Step 1: Create the Agent Logic

Create `src/agent.ts`:

```typescript
import { ActivityHandler, TurnContext, MessageFactory } from "botbuilder";
import { AzureOpenAI } from "openai";
import { DefaultAzureCredential, getBearerTokenProvider } from "@azure/identity";

export class EnterpriseTravelAgent extends ActivityHandler {
  private client: AzureOpenAI;

  constructor() {
    super();

    const credential = new DefaultAzureCredential();
    const tokenProvider = getBearerTokenProvider(
      credential,
      "https://cognitiveservices.azure.com/.default"
    );

    this.client = new AzureOpenAI({
      // Route through APIM gateway
      endpoint: process.env.APIM_GATEWAY_URL!,
      azureADTokenProvider: tokenProvider,
      apiVersion: "2025-11-18",
    });

    this.onMessage(async (context: TurnContext, next) => {
      const userMessage = context.activity.text;

      // Show typing indicator
      await context.sendActivity({ type: "typing" });

      try {
        // Call the enterprise agent via Foundry
        const response = await this.client.chat.completions.create({
          model: "model-router", // Use Model Router for smart routing
          messages: [
            {
              role: "system",
              content: `You are the Enterprise Travel Policy Advisor, embedded in Microsoft Teams.
              
You help employees with:
1. Travel policy questions - cite specific policy sections
2. Expense report reviews - check compliance
3. Travel bookings - coordinate flights and hotels
4. M365 integration - check calendars and emails for context

Be concise and format responses for Teams (use markdown).
Use adaptive cards for structured data when appropriate.`,
            },
            { role: "user", content: userMessage },
          ],
        });

        const reply = response.choices[0].message.content || "I couldn't process that request.";
        await context.sendActivity(MessageFactory.text(reply));
      } catch (error) {
        console.error("Agent error:", error);
        await context.sendActivity(
          "I encountered an error processing your request. Please try again."
        );
      }

      await next();
    });

    this.onMembersAdded(async (context, next) => {
      for (const member of context.activity.membersAdded || []) {
        if (member.id !== context.activity.recipient.id) {
          await context.sendActivity(
            `👋 Welcome! I'm the **Enterprise Travel Advisor**.\n\n` +
            `I can help you with:\n` +
            `- **Travel policy questions**: "What's the hotel limit for Paris?"\n` +
            `- **Expense reviews**: "Review my expense report for the London trip"\n` +
            `- **Travel bookings**: "Book a flight to Berlin next Tuesday"\n\n` +
            `How can I help?`
          );
        }
      }
      await next();
    });
  }
}
```

### Step 2: Create the Bot Adapter

Create `src/adapter.ts`:

```typescript
import { CloudAdapter, ConfigurationBotFrameworkAuthentication } from "botbuilder";

const botFrameworkAuth = new ConfigurationBotFrameworkAuthentication(
  {},
  undefined,
  undefined,
  undefined,
  {
    MicrosoftAppId: process.env.BOT_ID,
    MicrosoftAppPassword: process.env.BOT_PASSWORD,
    MicrosoftAppTenantId: process.env.BOT_TENANT_ID,
    MicrosoftAppType: "SingleTenant",
  }
);

export const adapter = new CloudAdapter(botFrameworkAuth);

adapter.onTurnError = async (context, error) => {
  console.error(`[onTurnError] ${error}`);
  await context.sendActivity("The bot encountered an error. Please try again.");
};
```

### Step 3: Create the Entry Point

Create `src/index.ts`:

```typescript
import express from "express";
import { adapter } from "./adapter";
import { EnterpriseTravelAgent } from "./agent";

const app = express();
app.use(express.json());

const agent = new EnterpriseTravelAgent();

// Bot Framework messages endpoint
app.post("/api/messages", async (req, res) => {
  await adapter.process(req, res, (context) => agent.run(context));
});

// Health check
app.get("/api/health", (req, res) => {
  res.json({ status: "healthy" });
});

const port = process.env.PORT || 3978;
app.listen(port, () => {
  console.log(`Enterprise Travel Agent listening on port ${port}`);
});
```

---

## Part 5: BYO Network Considerations

### Challenge

When the Hosted Agent is behind BYO VNet, the Custom Engine Agent needs to reach it. The bot itself runs as an App Service, which can be VNet-integrated.

### Solution Architecture

```
Teams → Bot Framework → App Service (VNet) → APIM (VNet) → Foundry (BYO VNet)
```

### Configuration Steps

1. **App Service VNet Integration**: Use the `snet-appservice` subnet
2. **Route all traffic through VNet**: Enable `vnetRouteAllEnabled`
3. **Access APIM via private endpoint**: Already configured in Chapter 01
4. **APIM routes to Foundry**: Already configured with private endpoints

```bash
# Ensure App Service has VNet integration
az webapp vnet-integration add \
  --resource-group $RESOURCE_GROUP \
  --name "app-travel-copilot" \
  --vnet $VNET_NAME \
  --subnet snet-appservice

# Route all outbound through VNet
az webapp config set \
  --resource-group $RESOURCE_GROUP \
  --name "app-travel-copilot" \
  --vnet-route-all-enabled true
```

---

## Part 6: Deploy and Test

### Step 1: Deploy with Teams Toolkit

```bash
# Provision infrastructure
npx teamsapp provision --env dev

# Deploy code
npx teamsapp deploy --env dev
```

### Step 2: Test in Teams

1. Open Microsoft Teams
2. Search for "Travel Advisor" in the apps
3. Start a conversation
4. Test queries:
   - "What is the per diem rate for Berlin?"
   - "Review my expense: 3 nights Munich at $290/night"
   - "Do I have any calendar conflicts next Tuesday?"

### Step 3: Sideload for Development

For development testing without publishing:

1. In Teams Toolkit → **Preview in Teams**
2. Or manually sideload: Teams → Apps → **Upload a custom app** → Select `appPackage.dev.zip`

---

## Summary

| Component | Status |
|-----------|--------|
| Custom Engine Agent scaffolded | ✅ |
| App manifest v1.21 configured | ✅ |
| Bot logic with APIM/Model Router integration | ✅ |
| VNet integration for secure connectivity | ✅ |
| Deployed to Teams | ✅ |
| End-to-end testing in Teams | ✅ |

---

## References

- [Custom Engine Agent Overview](https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/overview-custom-engine-agent)
- [Build Custom Engine Agents](https://microsoft.github.io/copilot-camp/pages/custom-engine/)
- [Microsoft 365 Agents Toolkit](https://learn.microsoft.com/en-us/microsoftteams/platform/toolkit/teams-toolkit-fundamentals)
- [App Manifest Schema](https://learn.microsoft.com/en-us/microsoftteams/platform/resources/schema/manifest-schema)

---

## Next Steps

Proceed to [Chapter 14 — Set Up Observability, Evaluation, and Guardrails](./14-observability.md)
