# ZIP-only hosted Echo MCP diagnostic

A minimal, model-free Python workload hosted by Microsoft Foundry. It tests:

```text
Approved client -> Foundry hosted runtime -> APIM Echo MCP -> response
```

It uses the **Invocations** protocol, not a conversational Responses agent.
There is no model call, container build, ACR, Function deployment, AWS discovery,
grounding, or memory integration. APIM's existing Echo API remains the MCP tool
backend; this sample does not replace it.

This is an independent diagnostic sample tracked by issue #109, not completion
evidence for the Phase 1 demo or the Chapter 08 hosted-agent follow-on.

## Network prerequisites

The MCP endpoint is private to the enterprise network. **Do not test it from an
unapproved public client.** The Foundry hosted runtime must already have an
approved outbound network path to APIM, including DNS resolution, routing,
firewall/NSG rules, TCP 443, and certificate trust for the selected gateway
hostname. A ZIP upload does not create that path or configure VNet injection.

The deployment client must reach the Foundry project data plane, and the
invocation client must reach the hosted-agent endpoint. Those paths are distinct
from hosted runtime -> APIM. A working laptop/VPN connection does not prove
hosted-runtime access. This code does not disable TLS verification, change DNS,
enable public access, or bypass APIM.

Bundling dependencies avoids package-index downloads during provisioning.
Foundry still requires its documented source-deployment outbound dependencies
(including `mcr.microsoft.com` and `*.login.microsoft.com`). Existing Foundry
network configuration, regional support, and permissions remain prerequisites.

## Package

From the repository root, with Python 3.13+ and pip:

```bash
python3.13 samples/hosted-echo-mcp/build_zip.py
```

On Windows, use `py -3.13` instead of `python3.13`. The builder downloads extracted
Linux x86_64 wheels for Python 3.13, regardless of the packaging machine's OS.
It writes a timestamped ZIP and SHA-256 file under ignored `tmp/`. It refuses to
overwrite an existing ZIP, checks integrity, and enforces the 250 MiB upload
limit. Only these files are included:

```text
main.py
requirements.txt
packages/...
```

No key, endpoint, `.env`, deployment script, tests, or local state is packaged.
`requirements.txt` pins the complete runtime dependency graph.

## Prepare the subscription-key connection

In the **existing Foundry project**, create an approved connection storing the
APIM subscription key. Use an `ApiKey` connection, whose secret field is `key`,
or a `CustomKeys` connection with an explicitly named `key` secret field.
For example, name the connection `echo-mcp`.

In [Foundry portal](https://ai.azure.com), select the same project identified by
`FOUNDRY_PROJECT_ENDPOINT`, then open
**Manage > Project details > Connected resources** and select **Add connection**.
Choose **API key** or **Custom key**, store the APIM
subscription key securely, and confirm the connection's resource name. For
Custom key, name the secret field exactly `key`. Set `APIM_KEY_CONNECTION_NAME`
to that resource name; `echo-mcp` is only an example. An APIM API/MCP server named
`echo-mcp` does not create a Foundry connection with that name.

Keep the key out of source files, ZIPs, command-line arguments, and logs. The
deployment helper supplies the runtime environment as:

```text
APIM_MCP_URL=<your exact APIM MCP HTTPS URL>
APIM_SUBSCRIPTION_KEY=${{connections.echo-mcp.credentials.key}}
```

Foundry validates referenced connection names when creating the agent version
and resolves their values at sandbox startup. A missing connection can reject
deployment with `bad_request` and `workspace connections ... were not found`.
The helper first checks the selected connection's existence using metadata only;
it does not fetch, validate, or print its secret fields. Permission and network
errors from that check stop deployment and are surfaced unchanged. This check
requires connection-read permission and does not prove runtime resolution.
If an empty or unresolved key reaches the runtime, invocation reports
`configuration_error`; readiness and deployment status alone do not prove
resolution. The subscription must be authorized for the MCP API/product, not
merely for the original Echo REST API.
This sample uses the default `Ocp-Apim-Subscription-Key` header.

## Deploy the ZIP yourself

No Azure deployment is performed when packaging. The optional Python helper
uses `create_version_from_code`, SHA-256, `python_3_13`, `bundled`,
`["python", "main.py"]`, and `invocations` version `2.0.0`. It targets only the
existing project and creates a version of an agent that must already exist there;
it does not create the agent itself. No supporting infrastructure or connection
is created.

If deployment reports that `echo-mcp` was not found, create the connection above
in the selected Foundry project, or set `APIM_KEY_CONNECTION_NAME` to an existing
compatible connection's exact name and retry. Increasing `--timeout`, rebuilding
the ZIP, or changing the APIM endpoint will not fix a missing connection.

Install the deployment-client dependencies into your own virtual environment:

```bash
python -m pip install -r samples/hosted-echo-mcp/deploy-requirements.txt
```

Install the complete deployment requirements with the same virtual-environment
interpreter used to run `deploy.py`. They explicitly include `httpx`, which the
Projects SDK imports; installing the runtime requirements is not necessary for
the deployment helper. Confirm the deployment-only installation without making
an Azure request:

```bash
python samples/hosted-echo-mcp/deploy.py --help
```

Sign in yourself using an approved Azure credential. Set these **local**
environment variables; substitute your actual values, but do not commit them:

```bash
export FOUNDRY_PROJECT_ENDPOINT="https://<account>.services.ai.azure.com/api/projects/<project>"
export APIM_MCP_URL="https://gateway.example.com/echo-mcp/mcp"
export APIM_KEY_CONNECTION_NAME="echo-mcp"
python samples/hosted-echo-mcp/deploy.py tmp/<timestamped-agent-zip>.zip
```

PowerShell equivalents:

```powershell
$env:FOUNDRY_PROJECT_ENDPOINT = "https://<account>.services.ai.azure.com/api/projects/<project>"
$env:APIM_MCP_URL = "https://gateway.example.com/echo-mcp/mcp"
$env:APIM_KEY_CONNECTION_NAME = "echo-mcp"
py -3.13 samples/hosted-echo-mcp/deploy.py tmp/<timestamped-agent-zip>.zip
```

The default name is `echo-mcp-connectivity`; override it with `--name`.
Provisioning polling stops after 600 seconds unless `--timeout` is specified.
Failed provisioning is surfaced with its error object. A timeout does not delete
the version; inspect it before retrying.

Alternatively, upload the ZIP using Foundry Toolkit's **Code / Local** source
deployment path, selecting the same runtime, entry point, dependency mode,
protocol, and environment variables. This sample does not include a Toolkit
manifest; configure those fields explicitly. Do not select a container/ACR path.
The CPU/memory pair is 0.5 vCPU / 1 GiB.

## Invoke: discover first, then call

Use an approved client that can reach Foundry. The hosted agent accepts structured
JSON; it does not interpret natural-language chat instructions. Acquire a
Foundry token for `https://ai.azure.com`, not an APIM subscription-key credential.

```powershell
$token = az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Foundry token acquisition failed" }
$uri = "$env:FOUNDRY_PROJECT_ENDPOINT/agents/echo-mcp-connectivity/endpoint/protocols/invocations?api-version=v1"
$headers = @{ Authorization = "Bearer $token" }
Invoke-RestMethod -Method Post -Uri $uri -Headers $headers `
  -ContentType "application/json" -Body '{"action":"list"}'
```

The response returns exact MCP tool names and their `input_schema`. Select a
read-only Echo operation and provide arguments matching **that returned schema**:

```json
{
  "action": "call",
  "tool": "<exact name returned by list>",
  "arguments": {}
}
```

The empty argument object is only valid if the selected schema permits it.
For example, if the tool requires `message`, supply a synthetic test string.
Do not assume the converted API's tool name or input shape. Submit the populated
JSON as the next invocation body. The agent initializes a new MCP session,
discovers tools (including pagination), validates arguments, and invokes only
the explicitly selected tool. Streamable HTTP JSON and SSE responses are
supported; legacy standalone SSE transport and OAuth are excluded.

Successful responses contain `status: pass`, `correlation_id`,
`protocol_version`, and `tools`; call responses also contain `tool` and `result`.
Failures return non-2xx HTTP responses with `status: fail`, an error code,
correlation ID, and a diagnostic message. The total MCP operation timeout is
45 seconds. Correlation IDs are sent to APIM using `x-correlation-id`; APIM
must be configured to capture this header if needed.

## Evidence and limitations

| Claim | Required evidence |
| --- | --- |
| Flat ZIP and Linux Python 3.13 dependencies | Builder integrity checks and extracted-package startup |
| MCP discovery/invocation contract | Local mock JSON/SSE, pagination, authentication-header, and schema tests |
| Failure behavior | Local invalid-input, auth rejection, tool error, DNS failure, and timeout tests |
| Live hosted-runtime access to private APIM | **BLOCKED until run inside the approved environment** |
| Connection resolution and live Echo result | **BLOCKED until deployment and explicit invocation** |

An `active` version or HTTP 200 from `/readiness` proves neither network access
nor an Echo tool call. This diagnostic does not validate APIM -> Foundry model
access, client -> APIM -> hosted-agent invocation, or Entra authorization at
APIM. Use synthetic payloads; MCP results may be visible to callers and
platform telemetry. Do not send sensitive content.

Local contract tests, after installing the runtime and deployment requirements:

```bash
cd samples/hosted-echo-mcp
OTEL_SDK_DISABLED=true python -m unittest -q test_echo_mcp
```

No enterprise MCP endpoint is contacted by these tests.

Verify the actual extracted ZIP with Python 3.13 (no MCP network access):

```bash
python3.13 samples/hosted-echo-mcp/check_zip.py tmp/<timestamped-agent-zip>.zip
```

This starts a local server using only the bundled runtime dependencies, checks
readiness, and confirms missing configuration fails explicitly. It terminates
the test server and removes only its temporary extraction directory.

## Sources

- [ZIP source deployment, bundled layout, supported runtimes, and firewall requirements](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-code?tabs=python)
- [Hosting protocols, port 8088, readiness, and connection-templated secrets](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent)
- [Add a connection to the selected Foundry project](https://learn.microsoft.com/en-us/azure/foundry/how-to/connections-add)
- [SDK connection metadata lookup without credentials](https://learn.microsoft.com/en-us/python/api/azure-ai-projects/azure.ai.projects.operations.connectionsoperations?view=azure-python)
- [Hosted-agent protocol choice, endpoint format, identity, and compute sizes](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)

Rollback: stop using the diagnostic endpoint and remove only its agent/version
through approved Foundry procedures. Existing APIM APIs and networking are
unchanged. Retain a shared connection if other workloads use it.
