# Chapter 18 — Azure Policy — Block Non-Compliant Deployments

## Objective

Deploy **Azure Policy definitions and initiatives** that prevent any AI workload from being deployed without the required security, networking, identity, and observability controls.

By the end of this lab, you will have:

- 8 custom policy definitions covering AI-specific compliance requirements
- A policy initiative (bundle) called "Secure Agent Factory Baseline"
- Policy assignments with **Deny** effect that block non-compliant deployments
- Remediation tasks for existing resources

---

## Why Azure Policy Is the First Control

Azure Policy is the **only control that cannot be bypassed by any role**. Even if someone has Owner permissions, a Deny policy blocks the action at the ARM layer:

```
Developer tries to deploy model without private networking
                    ↓
ARM evaluates Azure Policy
                    ↓
Policy effect = Deny
                    ↓
Deployment blocked — 403 RequestDisallowedByPolicy
```

---

## Prerequisites

| Requirement | Details |
|------------|---------|
| Lab 01 completed | Platform Engineering group with Resource Policy Contributor |
| Azure CLI | Logged in as Platform Engineering member |
| Subscription | Owner or Resource Policy Contributor |

---

## Part 1: Policy Definition — Allowed Models Only

### Step 1.1 — Create the Policy Definition

Only allow pre-approved AI models to be deployed:

```bash
cat > /tmp/policy-allowed-models.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.CognitiveServices/accounts/deployments"
        },
        {
          "not": {
            "field": "Microsoft.CognitiveServices/accounts/deployments/model.name",
            "in": "[parameters('allowedModels')]"
          }
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  },
  "parameters": {
    "allowedModels": {
      "type": "Array",
      "metadata": {
        "displayName": "Allowed AI Models",
        "description": "List of approved model names that can be deployed"
      },
      "defaultValue": [
        "gpt-4o",
        "gpt-4o-mini",
        "o3-mini",
        "text-embedding-ada-002",
        "text-embedding-3-large"
      ]
    },
    "effect": {
      "type": "String",
      "metadata": {
        "displayName": "Effect",
        "description": "Deny or Audit non-compliant deployments"
      },
      "allowedValues": ["Audit", "Deny", "Disabled"],
      "defaultValue": "Deny"
    }
  }
}
EOF

az policy definition create \
  --name "saf-allowed-models-only" \
  --display-name "[SAF] Allowed AI Models Only" \
  --description "Restricts AI model deployments to an approved list. Part of Secure Agent Factory baseline." \
  --rules /tmp/policy-allowed-models.json \
  --mode All \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

---

## Part 2: Policy Definition — Private Networking Required

### Step 2.1 — Deny Public Network Access for Cognitive Services

```bash
cat > /tmp/policy-private-networking.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.CognitiveServices/accounts"
        },
        {
          "field": "Microsoft.CognitiveServices/accounts/publicNetworkAccess",
          "notEquals": "Disabled"
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  },
  "parameters": {
    "effect": {
      "type": "String",
      "allowedValues": ["Audit", "Deny", "Disabled"],
      "defaultValue": "Deny"
    }
  }
}
EOF

az policy definition create \
  --name "saf-private-networking-required" \
  --display-name "[SAF] Private Networking Required for AI Services" \
  --description "Denies AI service accounts with public network access enabled." \
  --rules /tmp/policy-private-networking.json \
  --mode All \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

---

## Part 3: Policy Definition — Managed Identity Required

### Step 3.1 — Deny Deployments Without Managed Identity

```bash
cat > /tmp/policy-managed-identity.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "in": [
            "Microsoft.CognitiveServices/accounts",
            "Microsoft.MachineLearningServices/workspaces"
          ]
        },
        {
          "field": "identity.type",
          "notContains": "SystemAssigned"
        },
        {
          "field": "identity.type",
          "notContains": "UserAssigned"
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  },
  "parameters": {
    "effect": {
      "type": "String",
      "allowedValues": ["Audit", "Deny", "Disabled"],
      "defaultValue": "Deny"
    }
  }
}
EOF

az policy definition create \
  --name "saf-managed-identity-required" \
  --display-name "[SAF] Managed Identity Required for AI Resources" \
  --description "Denies AI resources without managed identity. No shared service accounts." \
  --rules /tmp/policy-managed-identity.json \
  --mode All \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

---

## Part 4: Policy Definition — Approved Regions Only

```bash
cat > /tmp/policy-approved-regions.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "in": [
            "Microsoft.CognitiveServices/accounts",
            "Microsoft.MachineLearningServices/workspaces",
            "Microsoft.CognitiveServices/accounts/deployments"
          ]
        },
        {
          "not": {
            "field": "location",
            "in": "[parameters('allowedRegions')]"
          }
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  },
  "parameters": {
    "allowedRegions": {
      "type": "Array",
      "metadata": {
        "displayName": "Allowed Regions",
        "description": "Regions where AI resources can be deployed"
      },
      "defaultValue": [
        "eastus2",
        "westus3",
        "swedencentral"
      ]
    },
    "effect": {
      "type": "String",
      "allowedValues": ["Audit", "Deny", "Disabled"],
      "defaultValue": "Deny"
    }
  }
}
EOF

az policy definition create \
  --name "saf-approved-regions-only" \
  --display-name "[SAF] Approved Regions Only for AI Resources" \
  --description "Restricts AI resource deployment to approved regions for data residency compliance." \
  --rules /tmp/policy-approved-regions.json \
  --mode All \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

---

## Part 5: Policy Definition — Diagnostic Logging Required

```bash
cat > /tmp/policy-diagnostics-required.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.CognitiveServices/accounts"
        }
      ]
    },
    "then": {
      "effect": "AuditIfNotExists",
      "details": {
        "type": "Microsoft.Insights/diagnosticSettings",
        "existenceCondition": {
          "allOf": [
            {
              "field": "Microsoft.Insights/diagnosticSettings/logs.enabled",
              "equals": "true"
            },
            {
              "field": "Microsoft.Insights/diagnosticSettings/metrics.enabled",
              "equals": "true"
            }
          ]
        }
      }
    }
  },
  "parameters": {}
}
EOF

az policy definition create \
  --name "saf-diagnostics-required" \
  --display-name "[SAF] Diagnostic Logging Required for AI Services" \
  --description "Audits AI services that do not have diagnostic settings configured." \
  --rules /tmp/policy-diagnostics-required.json \
  --mode All \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

---

## Part 6: Policy Definition — Customer-Managed Keys Required

```bash
cat > /tmp/policy-cmk-required.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.CognitiveServices/accounts"
        },
        {
          "field": "Microsoft.CognitiveServices/accounts/encryption.keySource",
          "notEquals": "Microsoft.KeyVault"
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  },
  "parameters": {
    "effect": {
      "type": "String",
      "allowedValues": ["Audit", "Deny", "Disabled"],
      "defaultValue": "Audit"
    }
  }
}
EOF

az policy definition create \
  --name "saf-cmk-required" \
  --display-name "[SAF] Customer-Managed Keys for AI Services" \
  --description "Audits or denies AI services not using customer-managed encryption keys." \
  --rules /tmp/policy-cmk-required.json \
  --mode All \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

---

## Part 7: Policy Definition — Defender for AI Required

```bash
cat > /tmp/policy-defender-required.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Security/pricings"
        },
        {
          "field": "name",
          "equals": "AI"
        },
        {
          "field": "Microsoft.Security/pricings/pricingTier",
          "notEquals": "Standard"
        }
      ]
    },
    "then": {
      "effect": "Audit"
    }
  },
  "parameters": {}
}
EOF

az policy definition create \
  --name "saf-defender-ai-required" \
  --display-name "[SAF] Defender for AI Must Be Enabled" \
  --description "Audits whether Defender for AI is enabled at Standard tier." \
  --rules /tmp/policy-defender-required.json \
  --mode All \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

---

## Part 8: Policy Definition — Deny Direct Model Access (APIM Only)

This is the **most critical policy** — it ensures all AI traffic flows through APIM:

```bash
cat > /tmp/policy-deny-direct-access.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.CognitiveServices/accounts"
        },
        {
          "field": "Microsoft.CognitiveServices/accounts/networkAcls.defaultAction",
          "equals": "Allow"
        }
      ]
    },
    "then": {
      "effect": "[parameters('effect')]"
    }
  },
  "parameters": {
    "effect": {
      "type": "String",
      "allowedValues": ["Audit", "Deny", "Disabled"],
      "defaultValue": "Deny"
    }
  }
}
EOF

az policy definition create \
  --name "saf-deny-direct-model-access" \
  --display-name "[SAF] Deny Direct Model Access — APIM Gateway Required" \
  --description "Denies AI services with open network ACLs. All traffic must flow through APIM AI Gateway." \
  --rules /tmp/policy-deny-direct-access.json \
  --mode All \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

---

## Part 9: Create Policy Initiative (Bundle)

### Step 9.1 — Bundle All Policies Into One Initiative

```bash
cat > /tmp/policy-initiative.json << 'EOF'
[
  {
    "policyDefinitionId": "/subscriptions/{subscriptionId}/providers/Microsoft.Authorization/policyDefinitions/saf-allowed-models-only",
    "parameters": {
      "effect": { "value": "Deny" },
      "allowedModels": { "value": ["gpt-4o", "gpt-4o-mini", "o3-mini", "text-embedding-ada-002", "text-embedding-3-large"] }
    }
  },
  {
    "policyDefinitionId": "/subscriptions/{subscriptionId}/providers/Microsoft.Authorization/policyDefinitions/saf-private-networking-required",
    "parameters": { "effect": { "value": "Deny" } }
  },
  {
    "policyDefinitionId": "/subscriptions/{subscriptionId}/providers/Microsoft.Authorization/policyDefinitions/saf-managed-identity-required",
    "parameters": { "effect": { "value": "Deny" } }
  },
  {
    "policyDefinitionId": "/subscriptions/{subscriptionId}/providers/Microsoft.Authorization/policyDefinitions/saf-approved-regions-only",
    "parameters": {
      "effect": { "value": "Deny" },
      "allowedRegions": { "value": ["eastus2", "westus3", "swedencentral"] }
    }
  },
  {
    "policyDefinitionId": "/subscriptions/{subscriptionId}/providers/Microsoft.Authorization/policyDefinitions/saf-diagnostics-required"
  },
  {
    "policyDefinitionId": "/subscriptions/{subscriptionId}/providers/Microsoft.Authorization/policyDefinitions/saf-cmk-required",
    "parameters": { "effect": { "value": "Audit" } }
  },
  {
    "policyDefinitionId": "/subscriptions/{subscriptionId}/providers/Microsoft.Authorization/policyDefinitions/saf-defender-ai-required"
  },
  {
    "policyDefinitionId": "/subscriptions/{subscriptionId}/providers/Microsoft.Authorization/policyDefinitions/saf-deny-direct-model-access",
    "parameters": { "effect": { "value": "Deny" } }
  }
]
EOF

# Replace subscription ID
SUB_ID=$(az account show --query id -o tsv)
sed -i "s/{subscriptionId}/$SUB_ID/g" /tmp/policy-initiative.json

az policy set-definition create \
  --name "saf-baseline-initiative" \
  --display-name "Secure Agent Factory — Baseline Initiative" \
  --description "Complete compliance baseline for the Secure Agent Factory. Enforces approved models, private networking, managed identity, approved regions, diagnostics, CMK, Defender, and APIM-only access." \
  --definitions /tmp/policy-initiative.json \
  --metadata '{"category": "Secure Agent Factory", "version": "1.0.0"}'
```

### Step 9.2 — Assign the Initiative to the Subscription

```bash
az policy assignment create \
  --name "saf-baseline-assignment" \
  --display-name "Secure Agent Factory Baseline" \
  --policy-set-definition "saf-baseline-initiative" \
  --scope "/subscriptions/$SUB_ID" \
  --enforcement-mode Default \
  --identity-type SystemAssigned \
  --location eastus2
```

---

## Part 10: Test Policy Enforcement

### Step 10.1 — Test Denied Model Deployment

```bash
# Try to deploy an unapproved model (should fail)
az cognitiveservices account deployment create \
  --resource-group rg-agent-factory-dev \
  --name foundry-agent-factory \
  --deployment-name "rogue-model" \
  --model-name "davinci-002" \
  --model-version "1" \
  --model-format "OpenAI" \
  --sku-capacity 1 \
  --sku-name "Standard"

# Expected error:
# RequestDisallowedByPolicy: Resource 'rogue-model' was disallowed by policy.
# Policy: [SAF] Allowed AI Models Only
```

### Step 10.2 — Test Denied Public Access

```bash
# Try to create AI service with public access (should fail)
az cognitiveservices account create \
  --name "rogue-ai-service" \
  --resource-group rg-agent-factory-dev \
  --kind "OpenAI" \
  --sku "S0" \
  --location eastus2 \
  --custom-domain "rogue-ai-service" \
  --public-network-access "Enabled"

# Expected error:
# RequestDisallowedByPolicy: Policy: [SAF] Private Networking Required
```

### Step 10.3 — Test Denied Missing Identity

```bash
# Try to create AI service without managed identity (should fail)
az cognitiveservices account create \
  --name "no-identity-ai" \
  --resource-group rg-agent-factory-dev \
  --kind "OpenAI" \
  --sku "S0" \
  --location eastus2

# Expected error:
# RequestDisallowedByPolicy: Policy: [SAF] Managed Identity Required
```

---

## Part 11: Compliance Dashboard

### Step 11.1 — Check Compliance State

```bash
# View compliance for the initiative
az policy state list \
  --policy-set-definition "saf-baseline-initiative" \
  --query "[].{Resource:resourceId, Policy:policyDefinitionName, Compliance:complianceState}" \
  --output table
```

### Step 11.2 — Create Compliance Workbook Query

Use this KQL in Azure Monitor Workbooks:

```kusto
PolicyResources
| where type == "microsoft.policyinsights/policystates"
| where properties.policySetDefinitionName == "saf-baseline-initiative"
| extend complianceState = tostring(properties.complianceState)
| extend policyName = tostring(properties.policyDefinitionName)
| extend resourceId = tostring(properties.resourceId)
| summarize
    Compliant = countif(complianceState == "Compliant"),
    NonCompliant = countif(complianceState == "NonCompliant")
    by policyName
| order by NonCompliant desc
```

---

## Policy Summary

| Policy | Effect | Purpose |
|--------|--------|---------|
| Allowed Models Only | **Deny** | Only approved models can be deployed |
| Private Networking Required | **Deny** | No public endpoints on AI services |
| Managed Identity Required | **Deny** | Every resource must have managed identity |
| Approved Regions Only | **Deny** | Data residency and sovereignty compliance |
| Diagnostic Logging Required | **Audit** | Flag resources without logging |
| Customer-Managed Keys | **Audit** | Track CMK adoption |
| Defender for AI Required | **Audit** | Ensure Defender is enabled |
| Deny Direct Model Access | **Deny** | Force all traffic through APIM |

---

## Summary

| Component | Status |
|-----------|--------|
| 8 custom policy definitions created | ✅ |
| Policy initiative bundled | ✅ |
| Initiative assigned to subscription | ✅ |
| Deny effects block non-compliant deployments | ✅ |
| Compliance dashboard configured | ✅ |
| Policy enforcement tested | ✅ |

---

## Next Steps

Proceed to [Chapter 19 — Network Foundation & APIM AI Gateway](./19-network-and-gateway.md)
