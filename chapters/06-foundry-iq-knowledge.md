# Chapter 06 — Create a Foundry IQ Knowledge Base

## Objective

Create a **Foundry IQ Knowledge Base** to ground your agents in enterprise data. Foundry IQ connects your agents to structured and unstructured data sources, enabling retrieval-augmented generation (RAG) with BYO networking support.

---

## Prerequisites

- Chapter 05 completed (Foundry with BYO VNet operational)
- Sample enterprise documents (PDFs, Word docs, or markdown files)
- Azure Blob Storage from Chapter 05

---

## Part 1: Understanding Foundry IQ

Foundry IQ is the intelligence layer that enables agents to retrieve and reason over enterprise data. It provides:

- **Knowledge Indexes** — Vectorized, searchable indexes of your enterprise documents
- **Automatic Chunking** — Smart document segmentation for optimal retrieval
- **Hybrid Search** — Combines vector similarity with keyword search
- **BYO VNet Support** — All data stays within your network boundary
- **Data Source Connectors** — Connect to Blob Storage, SharePoint, SQL databases, and more

---

## Part 2: Prepare Data Sources

### Step 1: Upload Sample Documents

```bash
STORAGE_NAME="stagentsplatform"
CONTAINER_NAME="knowledge-base"

# Create a container for knowledge base documents
az storage container create \
  --account-name $STORAGE_NAME \
  --name $CONTAINER_NAME \
  --auth-mode login

# Upload sample enterprise documents
az storage blob upload-batch \
  --account-name $STORAGE_NAME \
  --destination $CONTAINER_NAME \
  --source ./sample-docs/ \
  --auth-mode login
```

Create sample documents in `./sample-docs/`:

**travel-policy.md**:
```markdown
# Enterprise Travel Policy

## Flight Booking Rules
- Economy class for domestic flights under 4 hours
- Business class allowed for international flights over 6 hours
- Premium economy for flights between 4-6 hours
- Bookings must be made at least 14 days in advance for best rates

## Hotel Policy
- Maximum nightly rate: $250 domestic, $350 international
- Extended stay (7+ nights): negotiate corporate rates
- Preferred hotel chains: Marriott, Hilton, IHG

## Per Diem Rates
- Domestic: $75/day for meals
- Europe: €90/day for meals
- Asia: $65/day for meals
```

**expense-policy.md**:
```markdown
# Expense Report Policy

## Submission Timeline
- Expense reports must be submitted within 30 days of travel
- Receipts required for all expenses over $25
- Manager approval required for expenses over $500

## Approved Expense Categories
- Transportation (flights, trains, taxis, rideshare)
- Accommodation (hotels, Airbnb for stays > 5 days)
- Meals (within per diem limits)
- Conference fees and registrations
- Business entertainment (pre-approval required)
```

### Step 2: Ensure Private Access to Storage

Since we're using BYO VNet, ensure the storage account is only accessible via private endpoints:

```bash
# Verify storage account has no public access
az storage account show \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_NAME \
  --query "publicNetworkAccess" -o tsv
# Should return: Disabled

# Verify private endpoint exists
az network private-endpoint show \
  --resource-group $RESOURCE_GROUP \
  --name "pe-storage" \
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv
# Should return: Approved
```

---

## Part 3: Create the Knowledge Index

### Step 1: Create via Foundry Portal

1. Navigate to [Microsoft Foundry Portal](https://ai.azure.com)
2. Open your project
3. Go to **Knowledge** → **+ Create Knowledge Index**
4. Configure:
   - **Name**: `enterprise-policies`
   - **Description**: `Enterprise travel and expense policies for agent grounding`
   - **Data Source**: Azure Blob Storage
   - **Storage Account**: `stagentsplatform`
   - **Container**: `knowledge-base`
   - **Authentication**: Managed Identity (system-assigned)
5. Configure indexing:
   - **Chunking Strategy**: Auto (or configure custom chunk sizes)
   - **Embedding Model**: `text-embedding-ada-002` or `text-embedding-3-small`
   - **Search Type**: Hybrid (vector + keyword)
6. Select **Create**

### Step 2: Create via Python SDK

```python
import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

load_dotenv()

endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"]

with (
    DefaultAzureCredential() as credential,
    AIProjectClient(endpoint=endpoint, credential=credential) as project_client,
):
    # Create a knowledge index connected to blob storage
    index = project_client.indexes.create_or_update(
        name="enterprise-policies",
        description="Enterprise travel and expense policies",
        source={
            "type": "azure_blob_storage",
            "connection_id": "<storage-connection-id>",
            "container_name": "knowledge-base",
        },
        embedding_model="text-embedding-3-small",
        search_type="hybrid",
    )
    print(f"Knowledge index created: {index.name}")
```

### Step 3: Verify BYO VNet Connectivity

With BYO networking, all data retrieval flows through the single-tenant data proxy:

```
Agent Query → Data Proxy (in delegated subnet) → Private Endpoint → Storage Account
```

Verify the knowledge index can access data:

```python
# Test a query against the knowledge index
results = project_client.indexes.query(
    index_name="enterprise-policies",
    query="What is the per diem rate for Paris?",
    top=3,
)

for result in results:
    print(f"Score: {result.score:.4f}")
    print(f"Content: {result.content[:200]}...")
    print("---")
```

---

## Part 4: Connect Multiple Data Sources

Foundry IQ supports connecting to multiple data sources within a single project:

### Azure Blob Storage (Files)
```python
# Already configured above for policy documents
```

### SharePoint Online (Optional)
```python
# Connect to SharePoint for live document access
sharepoint_index = project_client.indexes.create_or_update(
    name="sharepoint-knowledge",
    description="Company SharePoint document library",
    source={
        "type": "sharepoint_online",
        "connection_id": "<sharepoint-connection-id>",
        "site_url": "https://contoso.sharepoint.com/sites/policies",
    },
    embedding_model="text-embedding-3-small",
)
```

### Azure SQL Database (Structured Data)
```python
# Connect to SQL for structured data grounding
sql_index = project_client.indexes.create_or_update(
    name="employee-directory",
    description="Employee directory from HR database",
    source={
        "type": "azure_sql",
        "connection_id": "<sql-connection-id>",
        "table_name": "Employees",
    },
)
```

---

## Part 5: Configure Index Refresh

Set up automatic index refresh to keep knowledge current:

1. In Foundry Portal → **Knowledge** → Select your index
2. Go to **Settings** → **Refresh Schedule**
3. Configure:
   - **Frequency**: Daily (or hourly for rapidly changing data)
   - **Time**: Off-peak hours
   - **Incremental**: Enable for large datasets

---

## Summary

| Component | Status |
|-----------|--------|
| Sample enterprise documents uploaded | ✅ |
| Knowledge index created (enterprise-policies) | ✅ |
| BYO VNet connectivity verified | ✅ |
| Private endpoint access confirmed | ✅ |
| Index query tested | ✅ |

---

## References

- [Foundry IQ Connect](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/foundry-iq-connect)
- [Foundry Agent Service Networking](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive)

---

## Next Steps

Proceed to [Chapter 07 — Build a Prompt Agent in Foundry](./07-prompt-agent.md)
