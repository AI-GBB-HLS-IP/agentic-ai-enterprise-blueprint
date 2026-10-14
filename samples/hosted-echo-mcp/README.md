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

## Prepare your workstation

Run commands from the repository root in the same terminal. Use Python 3.13+
for packaging; the bundled runtime is always Linux x86_64 Python 3.13, even if
your deployment interpreter is Python 3.14. The deployment client is separate
from the dependencies inside the ZIP.

On Bash/WSL/Linux/macOS, first confirm `python3 --version` is 3.13 or later
(substitute `python3.13` or `python3.14` if needed), then:

```bash
export DEPLOY_VENV="$HOME/.venvs/echo-mcp-deploy-$(date -u +%Y%m%dT%H%M%SZ)"
python3 -m venv "$DEPLOY_VENV" &&
"$DEPLOY_VENV/bin/python" -m pip install --upgrade \
  -r samples/hosted-echo-mcp/deploy-requirements.txt &&
"$DEPLOY_VENV/bin/python" samples/hosted-echo-mcp/deploy.py --help
```

On Windows PowerShell:

```powershell
$stamp = Get-Date -Format "yyyyMMddTHHmmss"
$env:DEPLOY_VENV = Join-Path $HOME ".venvs/echo-mcp-deploy-$stamp"
py -3.13 -m venv "$env:DEPLOY_VENV"
if ($LASTEXITCODE -ne 0) { throw "Virtual environment creation failed" }
$deployPython = Join-Path $env:DEPLOY_VENV "Scripts/python.exe"
& $deployPython -m pip install --upgrade -r samples/hosted-echo-mcp/deploy-requirements.txt
if ($LASTEXITCODE -ne 0) { throw "Deployment dependency installation failed" }
& $deployPython samples/hosted-echo-mcp/deploy.py --help
if ($LASTEXITCODE -ne 0) { throw "Deployment helper import failed" }
```

If `venv` creation fails because `ensurepip` is unavailable, install the
distribution's matching venv package named in the error (for example,
`python3-venv` or `python3.13-venv` on Debian/Ubuntu), then retry. Do not use
`--break-system-packages`. Installing with this exact virtual-environment
interpreter avoids modifying system-managed Python.

The helper targets Projects SDK **2.8.x** and its public
`project.agents.create_version_from_code(definition=..., code=<ZIP stream>, ...)`
contract. SDK 2.2 exposes code deployment under the beta subclient instead;
its stable `project.agents` has no such method. The public method moved to
`project.agents` and changed its arguments in SDK 2.3. This helper does not use
the old multipart `content=` model or fall back to another deployment path.
The deployment requirements explicitly include `httpx`; installing runtime
requirements is not necessary for the helper.

## Package

Build a new ZIP and retain its exact path:

```bash
export ZIP_PATH="tmp/hosted-echo-mcp_$(date -u +%Y%m%dT%H%M%SZ).zip"
"$DEPLOY_VENV/bin/python" samples/hosted-echo-mcp/build_zip.py --output "$ZIP_PATH"
```

PowerShell:

```powershell
$env:ZIP_PATH = "tmp/hosted-echo-mcp_$(Get-Date -Format 'yyyyMMddTHHmmss').zip"
& $deployPython samples/hosted-echo-mcp/build_zip.py --output "$env:ZIP_PATH"
if ($LASTEXITCODE -ne 0) { throw "ZIP build failed" }
```

If you already have a ZIP built from the same runtime source and pinned runtime
requirements, set `ZIP_PATH` to that existing file instead. Changes only to
`deploy.py`, `deploy-requirements.txt`, tests, or documentation do not require a
ZIP rebuild. Changes to `main.py` or runtime `requirements.txt` do.

The builder downloads extracted Linux x86_64 wheels for Python 3.13, regardless
of the packaging machine's OS. It writes a timestamped ZIP and SHA-256 file under
ignored `tmp/`. It refuses to overwrite an existing ZIP, checks integrity, and
enforces the 250 MiB upload
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

For the **API key** form, use the exact MCP URL for **Endpoint**, the authorized
APIM subscription key for **API Key**, and `echo-mcp` (or your selected name) for
**Connection Name**. Enter the key only in the portal's secret field. Do not
commit screenshots of the populated connection or its customer endpoint.

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

After pulling helper updates, reinstall deployment requirements into the
existing deployment environment and check imports before retrying:

```bash
"$DEPLOY_VENV/bin/python" -m pip install --upgrade \
  -r samples/hosted-echo-mcp/deploy-requirements.txt &&
"$DEPLOY_VENV/bin/python" samples/hosted-echo-mcp/deploy.py --help
```

Sign in yourself using an approved Azure credential. Set these **local**
environment variables; substitute your actual values, but do not commit them:

```bash
export FOUNDRY_PROJECT_ENDPOINT="https://<account>.services.ai.azure.com/api/projects/<project>"
export APIM_MCP_URL="https://gateway.example.com/echo-mcp/mcp"
export APIM_KEY_CONNECTION_NAME="echo-mcp"
"$DEPLOY_VENV/bin/python" -u samples/hosted-echo-mcp/deploy.py \
  "$ZIP_PATH" --name echo-mcp-connectivity --timeout 600
```

PowerShell equivalents:

```powershell
$env:FOUNDRY_PROJECT_ENDPOINT = "https://<account>.services.ai.azure.com/api/projects/<project>"
$env:APIM_MCP_URL = "https://gateway.example.com/echo-mcp/mcp"
$env:APIM_KEY_CONNECTION_NAME = "echo-mcp"
& $deployPython -u samples/hosted-echo-mcp/deploy.py `
  "$env:ZIP_PATH" --name echo-mcp-connectivity --timeout 600
if ($LASTEXITCODE -ne 0) { throw "Hosted-agent deployment failed" }
```

These values and `DEPLOY_VENV`/`ZIP_PATH` are local to the terminal; Git pulls and
new virtual environments do not restore them. Keep continuation backslashes
at the end of their lines without trailing spaces. Set `APIM_MCP_URL` to the
exact MCP endpoint, including its actual path and trailing slash if required;
it is not the original Echo REST API URL. Store the subscription key only in
the Foundry connection, not in these commands.

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

### Foundry playground

Open the deployed agent's playground and submit exactly this JSON object, without
trailing punctuation, extra fields, or wrapping it in an `"input"` string:

```json
{"action":"list"}
```

The sample accepts an Invocations request body, not a natural-language chat
message. A successful list response proves MCP initialization and discovery for
that request, not tool execution.

### Direct invocation from Bash/WSL

Use the same approved credential and project environment as deployment. This
example obtains a token in-process rather than printing it or placing it in a
command-line argument:

```bash
"$DEPLOY_VENV/bin/python" - <<'PY'
import os
import requests
from azure.identity import DefaultAzureCredential

endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"].rstrip("/")
with DefaultAzureCredential() as credential:
    token = credential.get_token("https://ai.azure.com/.default").token
    with requests.post(
        f"{endpoint}/agents/echo-mcp-connectivity/endpoint/protocols/invocations",
        params={"api-version": "v1"},
        headers={"Authorization": f"Bearer {token}"},
        json={"action": "list"},
        timeout=60,
    ) as response:
        print(response.text)
        response.raise_for_status()
PY
```

For a different deployment name, replace `echo-mcp-connectivity` here and in the
PowerShell URL below. For a tool call, replace the list request body with the
schema-matched call object described below.

### Direct invocation from PowerShell

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
JSON as the next playground input or direct invocation body.

If discovery actually returns `createResource` with an optional `body` property
of type `string`, the following matches that schema:

```json
{
  "action": "call",
  "tool": "createResource",
  "arguments": {
    "body": "hello-from-foundry"
  }
}
```

If that backend expects JSON content in the string, encode it rather than passing
an object as `body`:

```json
{
  "action": "call",
  "tool": "createResource",
  "arguments": {
    "body": "{\"message\":\"hello-from-foundry\"}"
  }
}
```

An empty `required` array means the MCP schema permits omitting `body`; it does
not establish what payload the backend accepts. `additionalProperties: false`
rejects argument names absent from that schema. Use this example only after
confirming the returned name/schema and that the operation targets an approved
Echo test backend. A name such as `createResource` does not prove absence of side
effects. This diagnostic does not automatically enforce read-only tool selection.

The agent initializes a new MCP session, discovers tools (including pagination),
validates arguments, and invokes only
the explicitly selected tool. Streamable HTTP JSON and SSE responses are
supported; legacy standalone SSE transport and OAuth are excluded.

Successful responses contain `status: pass`, `correlation_id`,
`protocol_version`, and `tools`; call responses also contain `tool` and `result`.
Failures return non-2xx HTTP responses with `status: fail`, an error code,
correlation ID, and a diagnostic message. The total MCP operation timeout is
45 seconds. Correlation IDs are sent to APIM using `x-correlation-id`; APIM
must be configured to capture this header if needed.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| `No module named 'azure'` or `'httpx'` | Install all deployment requirements with the exact interpreter used for `deploy.py`; do not install into a different Python environment. |
| `externally-managed-environment` | Create a real virtual environment above; do not override system Python protections. |
| `KeyError: 'FOUNDRY_PROJECT_ENDPOINT'` or another deployment variable | Restore all three deployment environment variables in the same terminal. Check `DEPLOY_VENV` and `ZIP_PATH` there too. |
| No `create_version_from_code` on `project.agents` | Pull the matching helper and reinstall its requirements; SDK 2.2 has the wrong public operation surface. |
| Connection not found / `workspace connections ... were not found` | Verify the project endpoint and exact Foundry connection name; create the approved connection in that project if missing. An APIM API name is not a Foundry connection. |
| Provisioning timeout or failure | Inspect the existing agent version and error before retrying; timeout does not delete it. |
| `invalid_request` | Submit the exact JSON body; `list` accepts neither a tool nor nonempty arguments. |
| `unknown_tool` / `invalid_arguments` | Use the exact returned tool name and that tool's input schema; do not guess names or pass objects to string arguments. |
| `configuration_error` | Verify runtime connection-template resolution and a nonempty `key` field; metadata lookup does not verify secrets. |
| `apim_http_error` | Check the reported APIM HTTP status, subscription authorization for the MCP API/product, policy, and route. |
| `mcp_connection_error` / `mcp_timeout` | Check hosted-runtime DNS, routing, TCP 443, TLS trust, and upstream availability; laptop/VPN access is not sufficient proof. |

## Evidence and limitations

| Claim | Required evidence |
| --- | --- |
| Flat ZIP and Linux Python 3.13 dependencies | Builder integrity checks and extracted-package startup |
| MCP discovery/invocation contract | Local mock JSON/SSE, pagination, authentication-header, and schema tests |
| Failure behavior | Local invalid-input, auth rejection, tool error, DNS failure, and timeout tests |
| Deployment / active version | Record the selected version's actual status; proves provisioning only |
| Connection resolution and live MCP discovery | Record `status: pass` from `list`; proves initialization/discovery for that environment and request |
| Live Echo execution | Record `status: pass`, selected tool, expected synthetic result, and correlation ID from `call`; **BLOCKED until explicitly verified** |
| Another client/agent -> APIM -> hosted agent via A2A | Separate integration and acceptance; **BLOCKED until checked** |
| API Center registration/discovery | Separate catalog integration and acceptance; **BLOCKED until checked** |

Operator testing on 2026-10-13 reported successful deployment and showed MCP tool
schemas returned in the playground. That is environment-specific deployment and
discovery evidence, not a reproducible production acceptance record. No successful
Echo call result, inbound A2A/APIM integration, or API Center registration evidence
is recorded here. Keep customer identifiers, secrets, and screenshots containing
them out of committed evidence. Use generic placeholders and synthetic payloads.

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
- [Projects SDK release history and source-deployment API changes](https://github.com/Azure/azure-sdk-for-python/blob/main/sdk/ai/azure-ai-projects/CHANGELOG.md)
- [Hosted-agent protocol choice, endpoint format, identity, and compute sizes](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)

Rollback: stop using the diagnostic endpoint and remove only its agent/version
through approved Foundry procedures. Existing APIM APIs and networking are
unchanged. Retain a shared connection if other workloads use it.
