# Chapter 11 — Create a Fabric IQ Agent (Optional)

## Objective

Build a **Fabric IQ Agent** that enables natural-language querying of your organization's data estate — Lakehouse tables, semantic models, and ontologies — within Microsoft Fabric.

> **Note**: This chapter is optional. Skip if your organization does not use Microsoft Fabric.

---

## Architecture Context: Data Intelligence at Enterprise Scale

### Where This Fits

Fabric IQ is the **data analytics intelligence** layer. While Foundry IQ handles document knowledge and Work IQ handles organizational context, Fabric IQ gives agents access to **structured data at scale** — terabytes of transactional data, semantic models, and business metrics.

### What You Will Achieve

- An agent that can **query Lakehouse tables** using natural language (no SQL required by end users)
- Integration with **Power BI semantic models** for business-ready metrics and KPIs
- Understanding of how Fabric IQ respects **row-level security** and data governance

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Natural Language to SQL** | Users ask questions in plain English; Fabric IQ generates and executes optimized queries |
| **Enterprise Data Access** | Agents can access terabytes of structured data without custom data pipelines |
| **Security Inheritance** | Row-level security from Power BI semantic models is automatically enforced |
| **Business Metrics** | Agents can reference pre-defined measures and KPIs for accurate business answers |
| **Cross-IQ Power** | Combine Fabric IQ data with Work IQ context for deeply informed business intelligence |

---

## Prerequisites

- Chapters 01-10 completed
- Microsoft Fabric capacity (F64 or higher recommended)
- Fabric workspace with at least one Lakehouse
- Power BI Pro or Premium Per User license

---

## Part 1: Understanding Fabric IQ

### What Is Fabric IQ?

Fabric IQ is an AI-powered natural language query engine for Microsoft Fabric. It allows agents and users to:

- **Ask questions in plain English** about data in Lakehouses
- **Query semantic models** without writing DAX
- **Traverse ontologies** for complex cross-domain queries
- **Get grounded answers** with citations back to source tables

### Architecture

```
User Question → Fabric IQ → Query Engine → Lakehouse / Semantic Model
                    ↓
              Natural Language Response (with data citations)
```

### Key Components

| Component | Description |
|-----------|-------------|
| **Lakehouse** | Delta Lake storage with SQL analytics endpoint |
| **Semantic Model** | Power BI data model with measures, relationships |
| **Ontology** | Business-level data catalog describing entities and relationships |
| **Fabric IQ Agent** | AI agent that translates natural language to queries |

---

## Part 2: Set Up the Fabric Lakehouse

### Step 1: Create the Lakehouse

Using the Fabric portal:

1. Navigate to your Fabric workspace
2. Select **+ New** → **Lakehouse**
3. Name it: `enterprise-analytics-lakehouse`
4. Select **Create**

### Step 2: Load Sample Data

Use a Fabric notebook to load sample enterprise data:

```python
# Cell 1: Create sample tables
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, DateType, IntegerType
from datetime import date

# Employee expenses table
expenses_data = [
    ("EXP001", "Jane Doe", "Engineering", "Flight", "NYC to London", 1200.00, date(2025, 6, 15)),
    ("EXP002", "Jane Doe", "Engineering", "Hotel", "London Hilton", 320.00, date(2025, 6, 15)),
    ("EXP003", "Jane Doe", "Engineering", "Meals", "London per diem", 90.00, date(2025, 6, 15)),
    ("EXP004", "John Smith", "Sales", "Flight", "SFO to Berlin", 950.00, date(2025, 6, 20)),
    ("EXP005", "John Smith", "Sales", "Hotel", "Berlin Marriott", 280.00, date(2025, 6, 20)),
    ("EXP006", "Alice Chen", "Marketing", "Conference", "AWS re:Invent", 1599.00, date(2025, 7, 1)),
    ("EXP007", "Bob Kumar", "Finance", "Flight", "BOS to Munich", 1100.00, date(2025, 7, 5)),
]

expenses_schema = StructType([
    StructField("expense_id", StringType(), False),
    StructField("employee_name", StringType(), False),
    StructField("department", StringType(), False),
    StructField("category", StringType(), False),
    StructField("description", StringType(), True),
    StructField("amount", DoubleType(), False),
    StructField("expense_date", DateType(), False),
])

df_expenses = spark.createDataFrame(expenses_data, expenses_schema)
df_expenses.write.format("delta").mode("overwrite").saveAsTable("expenses")
```

```python
# Cell 2: Travel approvals table
approvals_data = [
    ("TRV001", "Jane Doe", "London", date(2025, 6, 15), date(2025, 6, 18), "Approved", "Manager A"),
    ("TRV002", "John Smith", "Berlin", date(2025, 6, 20), date(2025, 6, 23), "Approved", "Manager B"),
    ("TRV003", "Alice Chen", "Las Vegas", date(2025, 7, 1), date(2025, 7, 4), "Pending", "Manager C"),
    ("TRV004", "Bob Kumar", "Munich", date(2025, 7, 5), date(2025, 7, 8), "Approved", "Manager A"),
]

approvals_schema = StructType([
    StructField("travel_id", StringType(), False),
    StructField("employee_name", StringType(), False),
    StructField("destination", StringType(), False),
    StructField("start_date", DateType(), False),
    StructField("end_date", DateType(), False),
    StructField("status", StringType(), False),
    StructField("approver", StringType(), False),
])

df_approvals = spark.createDataFrame(approvals_data, approvals_schema)
df_approvals.write.format("delta").mode("overwrite").saveAsTable("travel_approvals")
```

---

## Part 3: Create a Semantic Model

### Step 1: Create from Lakehouse

1. In your Lakehouse → **SQL analytics endpoint**
2. Select the tables: `expenses`, `travel_approvals`
3. Click **New semantic model**
4. Name: `Enterprise Travel Analytics`
5. Configure:
   - Add relationship: `expenses.employee_name` → `travel_approvals.employee_name`
   - Create measures:
     ```dax
     Total Expenses = SUM(expenses[amount])
     Average Expense = AVERAGE(expenses[amount])
     Approved Travel Count = COUNTROWS(FILTER(travel_approvals, travel_approvals[status] = "Approved"))
     ```

### Step 2: Prepare for AI/Copilot

To make the semantic model Fabric IQ-ready:

1. Open the model in Power BI Desktop or Service
2. For each table and column, add **descriptions**:
   - `expenses` table: "Employee expense reports with categories and amounts"
   - `amount` column: "Expense amount in USD"
   - `department` column: "Employee's department (Engineering, Sales, Marketing, Finance)"
3. Mark key columns as **Q&A synonyms**:
   - `employee_name` → "employee", "person", "staff member"
   - `category` → "type", "expense type"

---

## Part 4: Configure Fabric IQ Agent

### Step 1: Enable Fabric IQ on the Workspace

1. In Fabric workspace → **Settings** → **Power BI** → **Q&A**
2. Enable **Q&A with Copilot**
3. Select the semantic models to expose

### Step 2: Use GitHub Copilot Agent Mode

You can interact with Fabric IQ through VS Code using the GitHub Copilot `@FabricIQ` agent:

```
@FabricIQ What are the total expenses by department?
```

```
@FabricIQ Show me all approved travel requests for July 2025
```

```
@FabricIQ Which employee has the highest travel expenses?
```

### Step 3: Programmatic Access via Foundry

Connect Fabric IQ to your Foundry agent:

```python
# Create a connection from Foundry to Fabric
project_client.connections.create_or_update(
    name="fabric-analytics",
    connection_type="fabric",
    target="https://api.fabric.microsoft.com",
    credentials={"type": "managed_identity"},
    metadata={
        "workspace_id": "<fabric-workspace-id>",
        "semantic_model_id": "<semantic-model-id>",
    },
)
```

### Step 4: Add to Agent as Tool

```python
# Add Fabric IQ as a tool to the enterprise agent
fabric_tool = {
    "type": "fabric_iq",
    "connection_id": "<fabric-connection-id>",
    "description": "Query enterprise analytics data in Fabric Lakehouse",
    "semantic_model": "Enterprise Travel Analytics",
}
```

---

## Part 5: Test the Integration

### Natural Language Queries

Test these queries against your Fabric IQ agent:

```python
test_queries = [
    "What are the total travel expenses for Q3 2025?",
    "Which department spends the most on travel?",
    "Show me all pending travel approvals",
    "Compare hotel costs between London and Berlin",
    "What is the average expense per trip?",
]

for query in test_queries:
    response = openai_client.responses.create(
        input=query,
        extra_body={
            "agent_reference": {
                "name": "EnterprisePolicyAdvisorWithFabric",
                "type": "agent_reference",
            }
        },
    )
    print(f"Q: {query}")
    print(f"A: {response.output_text}\n")
```

---

## Summary

| Component | Status |
|-----------|--------|
| Fabric Lakehouse created with sample data | ✅ |
| Semantic model with measures and relationships | ✅ |
| Model descriptions and synonyms configured | ✅ |
| Fabric IQ enabled on workspace | ✅ |
| Natural language queries working | ✅ |
| Connected to Foundry agent (optional) | ✅ |

---

## References

- [Fabric IQ Overview](https://learn.microsoft.com/en-us/fabric/iq/overview)
- [Create a Semantic Model](https://learn.microsoft.com/en-us/fabric/data-warehouse/semantic-models)
- [Prepare Semantic Model for AI/Copilot](https://learn.microsoft.com/en-us/power-bi/create-reports/copilot-prepare-semantic-model)

---

## Next Steps

Proceed to [Chapter 12 — Configure Model Router](./12-model-router.md)
