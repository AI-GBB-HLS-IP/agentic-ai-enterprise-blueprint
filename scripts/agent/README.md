# Phase 1 agent deployment contract

The AKS deployment consumes an existing, owner-approved cluster. It does not provision an
AKS cluster or infer deployment targets. Supply these values in the calling environment; do not
commit environment-specific values:

| Variable | Required value |
|---|---|
| `AKS_CLUSTER_RESOURCE_ID` | Full resource ID of the approved AKS cluster |
| `AKS_NAMESPACE` | Approved namespace for the Phase 1 agent workloads |
| `AKS_INGRESS_PATTERN` | Owner-approved private ingress pattern reachable by required callers |
| `AKS_WORKLOAD_IDENTITY_ISSUER` | OIDC issuer URL configured for workload identity on the cluster |
| `AKS_CONTAINER_REGISTRY` | Approved registry endpoint and image source for the workloads |

Run `scripts/agent/preflight.sh` to check that the required inputs are supplied. Missing inputs
produce named `BLOCKED` results and a non-zero exit code. A `PENDING` result means only that the
input fields are populated; it does not verify approval, cluster access, OIDC configuration,
registry access, networking, private DNS, or ingress. Those live checks belong to the AKS
prerequisite validation in task 5.1.

## Shared lookup contract

`agents/contracts/lookup.openapi.json` defines the read-only lookup operation,
`lookup-fixture.json` contains its generic success data and reserved backend-failure identifier,
and `lookup-acceptance.json` provides common known-record, not-found, and backend-failure cases
for the Foundry prompt and AKS agent adapters. Run `tests/agent/test-lookup-contract.sh` to check
that the acceptance cases reference the same contract and fixture. Runtime adapter execution is
validated with the shared runner in task 10.1.

## Foundry model approval inputs

Foundry-dependent preflight also requires the approved region and deployment metadata for the
chat, embedding, and Foundry IQ query-planning models. For each model, supply its deployment
name, model version, approval reference, and capacity evidence reference:

| Model | Required variables |
|---|---|
| Chat | `CHAT_MODEL_DEPLOYMENT`, `CHAT_MODEL_VERSION`, `CHAT_MODEL_APPROVAL_REFERENCE`, `CHAT_MODEL_CAPACITY_EVIDENCE` |
| Embedding | `EMBEDDING_MODEL_DEPLOYMENT`, `EMBEDDING_MODEL_VERSION`, `EMBEDDING_MODEL_APPROVAL_REFERENCE`, `EMBEDDING_MODEL_CAPACITY_EVIDENCE` |
| Query planning | `QUERY_MODEL_DEPLOYMENT`, `QUERY_MODEL_VERSION`, `QUERY_MODEL_APPROVAL_REFERENCE`, `QUERY_MODEL_CAPACITY_EVIDENCE` |

Set `FOUNDRY_REGION` to the approved deployment region. Run
`scripts/agent/foundry-model-preflight.sh` to require all of these inputs. Missing approval or
capacity evidence is `BLOCKED`; populated references are `PENDING` until the responsible
subscription and regional capacity checks are performed. This preflight does not assert that
model approval or live quota has been verified.

## Foundry tool identity evidence

The tool integration requires separately approved tool and backend API audiences, a tenant,
issuer, token version, explicit caller principal IDs, and the selected Foundry OpenAPI
integration/API version. Supply these as `TOOL_API_TENANT_ID`, `TOOL_API_AUDIENCE`,
`BACKEND_API_AUDIENCE`, `TOOL_API_TOKEN_VERSION`, `TOOL_API_ISSUER`,
`TOOL_API_ALLOWED_PRINCIPAL_IDS` (comma-separated), `APIM_MANAGED_IDENTITY_PRINCIPAL_ID`,
`FOUNDRY_OPENAPI_INTEGRATION`, `FOUNDRY_OPENAPI_API_VERSION`,
`FOUNDRY_CALLER_PRINCIPAL_ID`, and approval references
`TOOL_API_APPROVAL_REFERENCE` and `BACKEND_API_APPROVAL_REFERENCE`.

After a Foundry tool call, provide `FOUNDRY_CALLER_EVIDENCE_FILE` as a path to a local,
untracked JSON file containing only the redacted claims `tenant_id`, `issuer`, `audience`,
`token_version`, `principal_id`, and `token_type`. Do not put tokens or authorization headers in
the file. `scripts/agent/foundry-tool-preflight.sh` blocks missing approvals/evidence, claim
mismatches, and an unapproved Foundry principal. It does not infer a caller from account/project
identity and does not treat a populated evidence file as proof of live authorization; a matching
contract remains `PENDING` until live integration validation is performed.

If multiple Foundry agents share the verified caller principal, they share the same POC tool
permission. Agent/project diagnostic identifiers do not provide per-agent authorization.

## Shared monitoring approval inputs

Supply the approved monitoring resource IDs and ownership evidence as
`MONITORING_WORKSPACE_RESOURCE_ID`, `MONITORING_AMPLS_RESOURCE_ID`,
`MONITORING_AMPLS_PRIVATE_ENDPOINT_ID`, `MONITORING_PRIVATE_DNS_OWNER_REFERENCE`, and
`MONITORING_OWNER_APPROVAL_REFERENCE`. Supply owner-approved association evidence for the
workspace, agent Application Insights component, and APIM Application Insights component using
`MONITORING_WORKSPACE_ASSOCIATION_EVIDENCE`, `AGENT_APPINSIGHTS_ASSOCIATION_EVIDENCE`, and
`APIM_APPINSIGHTS_ASSOCIATION_EVIDENCE`.

Record each sender's supported authentication and approved private-route evidence in
`AKS_TELEMETRY_AUTH_MODE`, `AKS_TELEMETRY_PRIVATE_ROUTE_EVIDENCE`,
`FOUNDRY_TELEMETRY_AUTH_MODE`, `FOUNDRY_TELEMETRY_PRIVATE_ROUTE_EVIDENCE`,
`APIM_TELEMETRY_AUTH_MODE`, and `APIM_TELEMETRY_PRIVATE_ROUTE_EVIDENCE`. The APIM logger remains
`instrumentation-key` authenticated for this POC; do not claim managed-identity authentication or
migrate it implicitly. `scripts/agent/monitoring-preflight.sh` blocks absent approvals/routes and
any APIM logger mode other than `instrumentation-key`. Present references remain `PENDING` until
the owner approvals, private routes, and telemetry arrival are validated live. No workspace or
AMPLS fallback is created.

## Sample corpus upload

Authenticate the Azure CLI with the approved managed or federated identity, then set
`UPLOAD_IDENTITY_CLIENT_ID`, `UPLOAD_IDENTITY_APPROVAL_REFERENCE`, `STORAGE_ACCOUNT_NAME`, and
`STORAGE_CONTAINER_NAME`. Run `scripts/agent/upload-sample-corpus.sh`; it uses login-based
authorization, overwrites only manifest-declared documents, and verifies the container has
exactly that document set. It does not remove unexpected blobs; it fails instead.

The POC shares resources only for the initial demonstration and a second-project
non-interference check on the same Foundry account. This does not establish production
multi-project isolation, business-unit accounts, capacity guarantees, chargeback, or retention
governance.

## Private endpoint parameter handoff

`infra/envs/poc/agent-private-endpoints.bicepparam.example` is a tracked placeholder example
for `infra/envs/poc/agent-private-endpoints.bicep`. Copy it to the ignored
`agent-private-endpoints.customer.bicepparam` in the same directory; replace placeholder IDs
with the actual shared-services deployment outputs and approved subnet, or export the
corresponding environment variables. Explicitly set all four `AGENT_PE_CREATE_*` variables
to `true` or `false` (or replace those expressions with explicit booleans in the local file).
Each `false` requires the full ID of an existing endpoint for that exact service/subresource.
The AMPLS scope and endpoint IDs are required owner-provided references: if either is unavailable,
this stage remains blocked. Do not substitute an unrelated endpoint.

Only after endpoint inventory, monitoring-owner inputs, and network-owner approval, review:

```bash
az deployment group what-if \
  --resource-group "<approved-resource-group>" \
  --template-file infra/envs/poc/agent-private-endpoints.bicep \
  --parameters infra/envs/poc/agent-private-endpoints.customer.bicepparam
```

This stage does not change the subnet NSG or route table, configure AMPLS, or associate private
DNS. It does not establish private reachability; validate connection approval and DNS separately
after the owner-approved association.
