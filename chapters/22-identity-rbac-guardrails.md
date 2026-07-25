# Chapter 22 — Identity, RBAC & Guardrails by Default

## Objective

Configure **per-agent managed identities**, **least-privilege RBAC**, and **mandatory guardrails** that are embedded in every Foundry project. No agent operates with shared credentials, and every agent output passes through content safety filters.

By the end of this lab, you will have:

- A user-assigned managed identity per agent (not per project)
- Entra ID Agent registration for Conditional Access
- Least-privilege RBAC with no standing admin access
- Content Safety filters with Prompt Shields, PII protection, and blocklists
- Tool call and tool response inspection

---

## The Identity Principle

```
Anti-Pattern:                           Secure Agent Factory:
┌──────────────┐                        ┌──────────────┐
│ Agent A      │                        │ Agent A      │
│ Agent B      │─── Shared Key ───→     │  MI: mi-agent-a │──→ Scoped Access
│ Agent C      │                        │ Agent B      │
└──────────────┘                        │  MI: mi-agent-b │──→ Scoped Access
  Cannot audit                          │ Agent C      │
  Cannot revoke individually            │  MI: mi-agent-c │──→ Scoped Access
  Cannot apply conditional access       └──────────────┘
                                          Full audit trail
                                          Revoke per agent
                                          Conditional Access per agent
```

---

## Prerequisites

| Requirement | Details |
|------------|---------|
| Lab 05 completed | At least one Foundry project provisioned |
| Logged in as | AI CoE member |

---

## Part 1: Per-Agent Managed Identity

### Step 1.1 — Create User-Assigned Managed Identity per Agent

```bash
PROJECT_NAME="customer-support"
AGENT_NAME="support-bot"

# Create user-assigned managed identity for this specific agent
az identity create \
  --resource-group rg-agent-factory-dev \
  --name "mi-${PROJECT_NAME}-${AGENT_NAME}" \
  --tags \
    "agent=$AGENT_NAME" \
    "project=$PROJECT_NAME" \
    "managedBy=ai-coe"
```

### Step 1.2 — Assign Minimum Required Roles

```bash
MI_PRINCIPAL_ID=$(az identity show \
  --resource-group rg-agent-factory-dev \
  --name "mi-${PROJECT_NAME}-${AGENT_NAME}" \
  --query principalId -o tsv)

MI_RESOURCE_ID=$(az identity show \
  --resource-group rg-agent-factory-dev \
  --name "mi-${PROJECT_NAME}-${AGENT_NAME}" \
  --query id -o tsv)

# Cognitive Services User on the project's AI Services (not Owner, not Contributor)
az role assignment create \
  --assignee-object-id $MI_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --role "Cognitive Services User" \
  --scope $(az cognitiveservices account show \
    --name "agent-${PROJECT_NAME}-dev" \
    --resource-group rg-agent-factory-dev \
    --query id -o tsv)

# Key Vault Secrets User (read secrets only, not manage)
az role assignment create \
  --assignee-object-id $MI_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope $(az keyvault show \
    --name kv-agent-factory \
    --resource-group rg-agent-factory-platform \
    --query id -o tsv)

# NO Contributor, NO Owner, NO Key Vault Administrator
```

### Step 1.3 — Register Agent as Entra ID Application

```bash
# Create app registration for the agent
az ad app create \
  --display-name "Agent: ${PROJECT_NAME}/${AGENT_NAME}" \
  --sign-in-audience AzureADMyOrg \
  --identifier-uris "api://agent-${PROJECT_NAME}-${AGENT_NAME}"

AGENT_APP_ID=$(az ad app list \
  --display-name "Agent: ${PROJECT_NAME}/${AGENT_NAME}" \
  --query "[0].appId" -o tsv)

# Create service principal
az ad sp create --id $AGENT_APP_ID

# Assign the managed identity as a federated credential
# (No client secrets — ever)
az ad app federated-credential create \
  --id $AGENT_APP_ID \
  --parameters '{
    "name": "mi-federation",
    "issuer": "https://login.microsoftonline.com/{tenant-id}/v2.0",
    "subject": "'$MI_PRINCIPAL_ID'",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

---

## Part 2: Conditional Access for Agent Identities

### Step 2.1 — Create Agent Security Group

```bash
az ad group create \
  --display-name "sg-agentfactory-agent-identities" \
  --mail-nickname "sg-agentfactory-agents" \
  --description "All agent managed identities in the Secure Agent Factory"

# Add agent's service principal to the group
az ad group member add \
  --group "sg-agentfactory-agent-identities" \
  --member-id $(az ad sp show --id $AGENT_APP_ID --query id -o tsv)
```

### Step 2.2 — Conditional Access Policy for Agents

Configure in Entra ID Admin Center:

| Setting | Value |
|---------|-------|
| **Name** | `CA-AgentFactory-AgentIdentities` |
| **Workload identities** | `sg-agentfactory-agent-identities` |
| **Cloud Apps** | Azure Cognitive Services, Azure Key Vault |
| **Conditions** | Named locations: Allow only corporate VNet IPs |
| **Grant** | Block access from non-corporate locations |

> **Effect**: Agent managed identities can only authenticate from within the corporate VNet. Even if credentials were somehow compromised, they cannot be used from outside.

---

## Part 3: Content Safety Guardrails

### Step 3.1 — Create Content Safety Configuration

```python
# guardrails_config.py — Included in every project blueprint
"""
Standard guardrails configuration for Secure Agent Factory.
Every agent call passes through these filters.
"""

from azure.ai.contentsafety import ContentSafetyClient
from azure.ai.contentsafety.models import (
    AnalyzeTextOptions,
    TextCategory,
)
from azure.identity import ManagedIdentityCredential


class AgentGuardrails:
    """Mandatory guardrails wrapper. Cannot be bypassed by developers."""

    def __init__(self, content_safety_endpoint: str):
        credential = ManagedIdentityCredential()
        self.client = ContentSafetyClient(content_safety_endpoint, credential)

        # Severity thresholds (AI CoE controlled, not developer configurable)
        self.thresholds = {
            TextCategory.HATE: 2,
            TextCategory.SELF_HARM: 2,
            TextCategory.SEXUAL: 2,
            TextCategory.VIOLENCE: 2,
        }

    def check_input(self, prompt: str) -> dict:
        """Check user input before sending to model."""
        result = self.client.analyze_text(
            AnalyzeTextOptions(
                text=prompt,
                categories=[
                    TextCategory.HATE,
                    TextCategory.SELF_HARM,
                    TextCategory.SEXUAL,
                    TextCategory.VIOLENCE,
                ],
            )
        )

        violations = []
        for category_result in result.categories_analysis:
            if category_result.severity >= self.thresholds.get(category_result.category, 2):
                violations.append({
                    "category": category_result.category,
                    "severity": category_result.severity,
                })

        return {
            "allowed": len(violations) == 0,
            "violations": violations,
        }

    def check_output(self, response: str) -> dict:
        """Check model output before returning to user."""
        return self.check_input(response)  # Same filters apply to output

    def check_tool_call(self, tool_name: str, arguments: dict) -> dict:
        """Inspect tool calls for suspicious patterns."""
        # Check for PII in tool arguments
        arg_text = str(arguments)
        input_check = self.check_input(arg_text)

        # Additional tool-specific checks
        suspicious_patterns = [
            "password", "secret", "token", "api_key",
            "credit_card", "ssn", "social_security",
        ]

        for pattern in suspicious_patterns:
            if pattern in arg_text.lower():
                input_check["allowed"] = False
                input_check["violations"].append({
                    "category": "PII_IN_TOOL_CALL",
                    "detail": f"Suspicious pattern '{pattern}' in tool arguments",
                })

        return input_check

    def check_tool_response(self, tool_name: str, response: str) -> dict:
        """Inspect tool responses for data leakage."""
        return self.check_output(response)
```

### Step 3.2 — Configure Prompt Shields

```python
# prompt_shield.py — Mandatory prompt injection defense
"""
Prompt Shield configuration. Detects and blocks prompt injection attempts.
"""

from azure.ai.contentsafety import ContentSafetyClient
from azure.ai.contentsafety.models import (
    ShieldPromptOptions,
    ShieldPromptResult,
)
from azure.identity import ManagedIdentityCredential


class PromptShield:
    """Detects prompt injection in user inputs and documents."""

    def __init__(self, content_safety_endpoint: str):
        credential = ManagedIdentityCredential()
        self.client = ContentSafetyClient(content_safety_endpoint, credential)

    def analyze(self, user_prompt: str, documents: list[str] = None) -> dict:
        """
        Analyze prompt for injection attacks.
        Returns: {"safe": bool, "attacks": [...]}
        """
        result = self.client.shield_prompt(
            ShieldPromptOptions(
                user_prompt=user_prompt,
                documents=documents or [],
            )
        )

        attacks = []
        if result.user_prompt_analysis and result.user_prompt_analysis.attack_detected:
            attacks.append({
                "source": "user_prompt",
                "type": "prompt_injection",
            })

        if result.documents_analysis:
            for i, doc_result in enumerate(result.documents_analysis):
                if doc_result.attack_detected:
                    attacks.append({
                        "source": f"document_{i}",
                        "type": "indirect_injection",
                    })

        return {
            "safe": len(attacks) == 0,
            "attacks": attacks,
        }
```

### Step 3.3 — Integrate Guardrails Into Agent Runtime

```python
# agent_runtime.py — Secure agent runtime wrapper
"""
Every agent in the Secure Agent Factory uses this runtime.
Guardrails are non-optional — they wrap every interaction.
"""

import logging
from guardrails_config import AgentGuardrails
from prompt_shield import PromptShield

logger = logging.getLogger("secure-agent-factory")


class SecureAgentRuntime:
    """
    Wraps agent execution with mandatory guardrails.
    Developers implement agent_logic() — everything else is enforced.
    """

    def __init__(self, agent_logic_fn, content_safety_endpoint: str):
        self.agent_logic = agent_logic_fn
        self.guardrails = AgentGuardrails(content_safety_endpoint)
        self.prompt_shield = PromptShield(content_safety_endpoint)

    async def process(self, user_input: str, context: dict = None) -> str:
        # 1. Prompt Shield — Block injection attempts
        shield_result = self.prompt_shield.analyze(user_input)
        if not shield_result["safe"]:
            logger.warning(f"Prompt injection blocked: {shield_result['attacks']}")
            return "I cannot process this request. It has been flagged for security review."

        # 2. Input Guardrails — Check content safety
        input_check = self.guardrails.check_input(user_input)
        if not input_check["allowed"]:
            logger.warning(f"Input blocked: {input_check['violations']}")
            return "Your input contains content that violates our usage policy."

        # 3. Execute agent logic (developer's code)
        response = await self.agent_logic(user_input, context)

        # 4. Output Guardrails — Check model response
        output_check = self.guardrails.check_output(response)
        if not output_check["allowed"]:
            logger.warning(f"Output blocked: {output_check['violations']}")
            return "The response was filtered due to content policy. Please rephrase your question."

        return response
```

---

## Part 4: Blocklists and Custom Rules

### Step 4.1 — Create Organization-Specific Blocklist

```bash
# Create a blocklist for organization-specific terms
az rest --method PUT \
  --url "https://agent-customer-support-dev-safety.cognitiveservices.azure.com/contentsafety/text/blocklists/org-blocklist?api-version=2024-09-01" \
  --headers "Content-Type=application/json" \
  --body '{
    "description": "Organization-specific blocked terms and patterns"
  }'

# Add blocklist items
az rest --method POST \
  --url "https://agent-customer-support-dev-safety.cognitiveservices.azure.com/contentsafety/text/blocklists/org-blocklist:addOrUpdateBlocklistItems?api-version=2024-09-01" \
  --headers "Content-Type=application/json" \
  --body '{
    "blocklistItems": [
      {"description": "Competitor product names", "text": "competitor-product-a"},
      {"description": "Internal project codenames", "text": "project-phoenix"},
      {"description": "Unreleased feature names", "text": "feature-quantum"}
    ]
  }'
```

---

## Part 5: RBAC Verification Matrix

### Step 5.1 — Verify No Privilege Escalation Paths

```bash
# List all role assignments on the dev resource group
az role assignment list \
  --resource-group rg-agent-factory-dev \
  --query "[].{Principal:principalName, Role:roleDefinitionName, Scope:scope}" \
  -o table

# Verify no standing Owner or Contributor for developers
az role assignment list \
  --resource-group rg-agent-factory-dev \
  --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor'].{Principal:principalName, Role:roleDefinitionName}" \
  -o table
# Expected: Only AI CoE members, no developers

# Verify agent managed identities have minimal roles
az role assignment list \
  --assignee $MI_PRINCIPAL_ID \
  --all \
  --query "[].{Role:roleDefinitionName, Scope:scope}" \
  -o table
# Expected: Only "Cognitive Services User" and "Key Vault Secrets User"
```

---

## Summary

| Component | Status |
|-----------|--------|
| Per-agent user-assigned managed identity | ✅ |
| Entra ID app registration per agent | ✅ |
| Federated credentials (no secrets) | ✅ |
| Conditional Access for agent identities | ✅ |
| Content Safety filters (input/output) | ✅ |
| Prompt Shields (injection detection) | ✅ |
| Tool call inspection | ✅ |
| Tool response inspection | ✅ |
| Organization blocklist | ✅ |
| Secure agent runtime wrapper | ✅ |
| RBAC privilege escalation verified | ✅ |

---

## Next Steps

Proceed to [Chapter 23 — Tool Governance & Approved MCP Registry](./23-tool-governance.md)
