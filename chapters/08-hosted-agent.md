# Chapter 08 - Build a Hosted Agent in Foundry

## Objective

Deploy custom code as a Microsoft Foundry Hosted Agent, using either a source
ZIP or a container image. Keep deployment, tool connectivity, and enterprise
publication as separate acceptance steps.

The [ZIP-only Echo MCP diagnostic](../samples/hosted-echo-mcp/README.md) is the
repository's runnable, model-free example. It uses the **Invocations** protocol
to call an existing APIM MCP endpoint. The Enterprise Travel Agent from
[Chapter 03](./03-agent-framework.md) remains a separate hosted-agent follow-on:
its hosting adapter, identity, model/tool access, persistence, and publication
must be validated before it is considered deployed.

## Choose a deployment path

| Path | What you supply | Repository coverage |
| --- | --- | --- |
| Source ZIP, bundled dependencies | Code, extracted Linux dependencies, runtime/entry point, protocol | Echo MCP sample: Linux x86_64 Python 3.13, no Docker/ACR or model call |
| Container image | A Linux amd64 image implementing a Foundry hosting protocol | Conditional SDK recipe below; requires a prepared and tested hosting adapter |
| Inbound A2A through APIM and API Center discovery | A validated A2A interface, gateway authentication/routing, and catalog entry | Follow-on acceptance, **BLOCKED until checked**; not supplied by the Echo sample |

These are different traffic paths:

```text
Approved client -> Foundry hosted agent -> APIM -> MCP tool
Another client/agent -> APIM -> hosted agent via A2A
API Center -> catalog discovery of the approved agent interface
```

A successful outbound MCP call does not prove inbound A2A gateway routing.
Deployment does not automatically import an APIM API or register an API Center
entry. The A2A and catalog goals remain in scope for the follow-on; they are not
completed merely because the hosted agent is running.

## Prerequisites and ownership

- An existing Foundry project in a region supporting the selected hosted runtime.
- An approved credential with **Foundry Project Manager** deployment permissions;
  connection metadata lookup also needs connection-read permission.
- The exact project endpoint:
  `https://<account>.services.ai.azure.com/api/projects/<project>`.
- Approved client access to the Foundry data plane and hosted endpoint.
- For private tools, a separately configured hosted-runtime outbound path:
  DNS, routing, firewall/NSG rules, TCP 443, TLS trust, and tool authorization.
- For the container path only, Docker/build tooling, an existing ACR, approved
  push/pull access, and the prepared application hosting adapter.

Reuse the infrastructure from [Chapter 01](./01-foundry-byo-networking.md) and
the gateway from [Chapter 02](./02-ai-gateway.md). Do not create or modify shared
networking, identities, APIM APIs, or catalog resources just to run a diagnostic.
Infrastructure/network owners configure those surfaces; developers deploy and
test approved code. A laptop/VPN connection proves only the client's path, not
hosted-runtime egress.

## Part 1: Deploy the runnable source ZIP diagnostic

Follow the [complete Echo MCP runbook](../samples/hosted-echo-mcp/README.md):

1. Create an isolated Python 3.13+ deployment environment and install its complete
   deployment requirements with that environment's interpreter.
2. Build a timestamped bundled ZIP, or select an existing ZIP with unchanged
   runtime source and runtime requirements.
3. In the selected Foundry project, create an approved API key connection
   containing the APIM subscription key. `echo-mcp` is an example connection
   name, not an automatically created connection.
4. Set `FOUNDRY_PROJECT_ENDPOINT`, `APIM_MCP_URL`, and
   `APIM_KEY_CONNECTION_NAME` in the same terminal, then run `deploy.py`.
5. Wait for `active`, invoke `{"action":"list"}`, then explicitly call an approved
   Echo tool using its returned name and input schema.

The helper targets Projects SDK **2.8.x**. Stable
`project.agents.create_version_from_code` first moved from the beta subclient in
SDK 2.3, with a changed argument contract. Use the matching checked-in helper
and `deploy-requirements.txt`, not a copied older SDK example.

The uploaded ZIP contains `main.py`, runtime `requirements.txt`, and `packages/`.
It does not contain deployment dependencies, keys, endpoints, or local state.
Updating only the deployment helper, its dependencies, tests, or docs does not
require rebuilding the ZIP. Runtime code/dependency changes do.

This diagnostic is not a conversational Travel Agent or evidence that Chapter
03's A2A server can be uploaded unchanged.

## Part 2: Prepare a container-based application

This section describes the current container deployment contract, not a complete
Travel Agent implementation. **BLOCKED before application deployment:** provide
and test the application-specific Foundry hosting adapter.

Choose a protocol that the application actually implements:

| Use case | Protocol | Python hosting library |
| --- | --- | --- |
| Conversational application | `responses` | `azure-ai-agentserver-responses` |
| Structured requests / custom processing | `invocations` | `azure-ai-agentserver-invocations` |
| Bidirectional streaming | `invocations_ws` | `azure-ai-agentserver-invocations` |

The conditional example below uses **Responses** for a conversational
application. It does not change the Echo sample's Invocations protocol or
provide an A2A adapter. Merely adding a protocol to the agent definition does
not implement its request handler.

Your `host.py` must start the selected Foundry hosting library on **port 8088**
and implement the application handler; the library supplies `/readiness`.
Use the [official hosting contract](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent#container-requirements)
and [framework samples](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents)
to prepare that adapter. The Chapter 03 `uvicorn a2a_server:server` command on
port 8000 is not a substitute for this contract. This chapter does not supply
`host.py` or a pinned application `requirements.txt`.

For a prepared application folder, the Dockerfile shape is:

```dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8088
CMD ["python", "host.py"]
```

Exclude `.env`, keys, local virtual environments, and other local artifacts
using the application's `.dockerignore`; pin its dependencies and choose an
approved image tag/digest under your release process.

From that application folder, substitute your existing ACR and an immutable
image tag:

```bash
export ACR_NAME="<existing-acr-name>"
export IMAGE_TAG="<unique-release-tag>"
az acr login --name "$ACR_NAME" &&
ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)" &&
export HOSTED_IMAGE="$ACR_LOGIN_SERVER/enterprise-travel-agent:$IMAGE_TAG" &&
docker build --platform linux/amd64 -t "$HOSTED_IMAGE" . &&
docker push "$HOSTED_IMAGE"
```

Confirm the build and push succeed before creating a version. The local build
must target **linux/amd64**, including on ARM development machines. Build and
dependency downloads require the appropriate approved network access.

The platform owner must grant the **project managed identity**, not an
assumed account identity, access to pull from ACR. Select the appropriate
registry-role model: **Container Registry Repository Reader** for an
ABAC-enabled registry, or **AcrPull** for its legacy registry-wide permission
mode. Do not assume assigning one role satisfies both modes. Verify pull
access and any private-registry restrictions in the selected environment
using [ACR role guidance](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-built-in-roles-overview).

## Part 3: Create a container agent version and wait for active

Reuse the isolated deployment environment from the Echo runbook and its current
SDK dependencies. Set the following local values for the prepared application:

```bash
export FOUNDRY_PROJECT_ENDPOINT="https://<account>.services.ai.azure.com/api/projects/<project>"
export HOSTED_AGENT_NAME="enterprise-travel-agent-hosted"
export MODEL_DEPLOYMENT_NAME="<existing-approved-model-deployment>"
```

`HOSTED_IMAGE` comes from the successful build/push above. Store this deployment
snippet in your approved application workspace, not in the container image, and
run it with `"$DEPLOY_VENV/bin/python"`:

```python
import os
import time

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    ContainerConfiguration,
    HostedAgentDefinition,
    ProtocolVersionRecord,
)
from azure.identity import DefaultAzureCredential

endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"].rstrip("/")
name = os.environ["HOSTED_AGENT_NAME"]

with (
    DefaultAzureCredential() as credential,
    AIProjectClient(endpoint=endpoint, credential=credential) as project,
):
    created = project.agents.create_version(
        agent_name=name,
        definition=HostedAgentDefinition(
            cpu="1",
            memory="2Gi",
            container_configuration=ContainerConfiguration(
                image=os.environ["HOSTED_IMAGE"],
            ),
            protocol_versions=[
                ProtocolVersionRecord(protocol="responses", version="2.0.0"),
            ],
            environment_variables={
                "MODEL_DEPLOYMENT_NAME": os.environ["MODEL_DEPLOYMENT_NAME"],
            },
        ),
    )
    print(f"Created version {created.version}", flush=True)
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        version = project.agents.get_version(
            agent_name=name, agent_version=created.version,
        )
        status = version["status"]
        print(f"Version {created.version}: {status}", flush=True)
        if status == "active":
            break
        if status == "failed":
            raise RuntimeError(f"Provisioning failed: {version.get('error')}")
        time.sleep(min(5, max(0, deadline - time.monotonic())))
    else:
        raise TimeoutError("Inspect the existing version before retrying deployment.")
```

`MODEL_DEPLOYMENT_NAME` is an application contract for this example: the prepared
handler must read it and use approved runtime credentials. The platform injects
`FOUNDRY_PROJECT_ENDPOINT` into the hosted runtime; do not redeclare it in the
version's environment map. External model/tool permissions remain separate
runtime prerequisites. Do not package your local Azure login.

Current SDK configuration uses `ContainerConfiguration(image=...)`, string
CPU/memory values, and explicit `protocol_versions`. Do not use the previous
top-level `container_image`, `container_port`, `min_replicas`, or `max_replicas`
fields. An `active` version proves provisioning, not correct business logic,
model access, memory, or tool connectivity.

## Part 4: Invoke the actual declared protocol

For the Echo diagnostic, use its [playground and direct-invocation instructions](../samples/hosted-echo-mcp/README.md#invoke-discover-first-then-call).
Send JSON directly to Invocations, not a Responses/chat payload:

```json
{"action":"list"}
```

For the prepared **Responses** container only, bind the client to the hosted
agent endpoint. Run this from an approved client with the same project/name
environment and deployment SDK:

```python
import os

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

with (
    DefaultAzureCredential() as credential,
    AIProjectClient(
        endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        credential=credential,
    ) as project,
    project.get_openai_client(
        agent_name=os.environ["HOSTED_AGENT_NAME"],
    ) as client,
):
    response = client.responses.create(
        input="Describe your supported travel-planning capabilities.",
    )
    print(response.output_text)
```

This can incur model charges. It is not a tool booking request or an A2A test.
The Invocations endpoint has the form
`<project-endpoint>/agents/<name>/endpoint/protocols/invocations?api-version=v1`;
do not guess an A2A URL from an agent name or assume the project-level Responses
client invokes a hosted agent without endpoint binding.

## Part 5: Private networking and identity checks

Use the existing approved Foundry network configuration. A ZIP upload or image
deployment does not itself configure BYO VNet injection, private endpoints,
DNS, firewall rules, or downstream access.

Validate three distinct paths: deployment client -> Foundry, invocation client
-> hosted endpoint, and hosted runtime -> models/tools. Source-code deployment
also needs the documented outbound dependencies, including `mcr.microsoft.com`
and `*.login.microsoft.com`; bundling Python dependencies avoids package-index
downloads but does not eliminate those platform dependencies. Check the
selected deployment path's telemetry and registry dependencies separately.

The platform assigns a hosted agent identity. Confirm its access to each
external resource instead of assuming that your CLI credential, project
identity, or Chapter 03 App Service identity is reused. The container recipe
does not configure durable application memory or private networking. Keep
unverified runtime DNS/TLS/routing, identity, persistence, and telemetry checks
**BLOCKED** until evaluated in the approved environment.

## Part 6: A2A publication through APIM and API Center

**Pending verification, not a completed capability.** Preserve the intended
inbound path: another client/agent -> APIM -> hosted agent via A2A, with API Center
catalog discovery. The Echo sample supplies neither that adapter/gateway route
nor the catalog entry. The conditional Responses container recipe also does not
establish an A2A endpoint.

Before publishing, the owning application/platform teams must:

1. Implement or identify the supported A2A adapter, protocol version, agent card,
   and actual endpoint; validate discovery and invocation against that contract.
2. Confirm the incoming caller authentication and APIM's backend authentication
   are both correct. Client JWT validation alone does not provide APIM with a
   valid Foundry backend credential.
3. Configure an approved APIM API with verified path rewriting, streaming where
   required, rate limits, authentication, and correlation/telemetry. Use the
   Chapter 02 `endpointAccess.selectedGatewayUrl` for `APIM_GATEWAY_URL`; keep
   the actual Foundry backend URL distinct from this client-facing gateway URL.
4. Verify another client/agent can discover and invoke through APIM, including
   negative authentication tests, routing, and backend authorization.
5. Register the verified interface through the approved API Center process and
   confirm its metadata, caller visibility, and catalog discovery.

Do not copy a guessed `/.well-known/agent.json`, `/a2a`, `tasks/send` payload,
OpenAPI mapping, or catalog command from an older protocol revision and call
the integration complete. Retain a named **BLOCKED** gate for each unverified
surface; this chapter does not change the existing core-catalog scope.

## Acceptance and evidence

| Check | Evidence needed / current boundary |
| --- | --- |
| Echo ZIP deployment | Operator reported deployment on 2026-10-13; record version/status for each new environment |
| Hosted runtime -> APIM MCP discovery | Operator showed returned schemas; record `status: pass`, correlation ID, and tool schemas |
| Explicit Echo execution | `call` returns `status: pass` and the expected synthetic result; **BLOCKED until recorded** |
| Travel container and Responses adapter | Build, pull, provisioning, handler and model/tool tests; **BLOCKED until performed** |
| BYO networking, runtime identity, persistence, telemetry | Environment-specific positive/negative checks; not inherited from a running version |
| Another client/agent -> APIM -> hosted agent via A2A | Verified A2A discovery, invocation, caller/backend auth, and routing; **BLOCKED until checked** |
| API Center registration and discovery | Verified catalog entry and intended-user discovery; **BLOCKED until checked** |

The reported Echo deployment/discovery is not a production approval or completion
of the Travel Agent follow-on. Keep all committed evidence generic: no customer
names, endpoints, identifiers, keys, or screenshots containing them.

## References

- [Source ZIP deployment and runtime/network requirements](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-code?tabs=python)
- [Container SDK deployment, protocols, port 8088, and permissions](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent)
- [Hosted-agent protocols and session lifecycle](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)
- [Private networking](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks)
- [Projects SDK release history](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/CHANGELOG.md)

## Next steps

After the applicable checks pass, continue to
[Chapter 09 - Connect Your Agent with Work IQ](./09-work-iq.md).

## Phase 1 scope: hosted-agent follow-on

The Foundry-managed Hosted Agent described in this chapter is a follow-on to the initial Phase 1
demonstration, not a substitute for its AKS-hosted code agent or a gate for initial acceptance.
The initial demo pairs a Foundry prompt agent with an independent AKS agent and supports
repeatable project onboarding on one Foundry account, including a second-project
non-interference check. The follow-on requires separate identity, networking, persistence, and
telemetry feasibility before implementation. Business-unit accounts and permanent production
isolation, capacity, chargeback, and retention topology are deferred.

Track the scope in [issue #83](https://github.com/AI-GBB-HLS-IP/agentic-ai-enterprise-blueprint/issues/83)
and the [OpenSpec change](../openspec/changes/add-phase1-agent-value-demo/proposal.md). This
chapter's deployment examples describe the Foundry-managed Hosted Agent only; they do not prove
the AKS deployment path or Phase 1 acceptance. Where the follow-on supports them, it should reuse
the sample corpus, knowledge and tool contracts, and common acceptance suite rather than assume
that AKS identity, network, memory, or telemetry configuration transfers to the Foundry runtime.
