import argparse
import hashlib
import os
import re
import time
import zipfile
from pathlib import Path
from urllib.parse import urlsplit

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import CodeConfiguration, HostedAgentDefinition, ProtocolVersionRecord
from azure.identity import DefaultAzureCredential


def deployment_definition(mcp_url: str, connection: str) -> HostedAgentDefinition:
    parsed = urlsplit(mcp_url)
    if (
        parsed.scheme != "https" or not parsed.hostname
        or parsed.username or parsed.password or parsed.query or parsed.fragment
    ):
        raise ValueError("APIM_MCP_URL must be an HTTPS MCP URL without credentials or query parameters.")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", connection):
        raise ValueError("Connection name must contain only letters, digits, underscores, or hyphens.")
    return HostedAgentDefinition(
        cpu="0.5",
        memory="1Gi",
        code_configuration=CodeConfiguration(
            runtime="python_3_13",
            entry_point=["python", "main.py"],
            dependency_resolution="bundled",
        ),
        protocol_versions=[ProtocolVersionRecord(protocol="invocations", version="2.0.0")],
        environment_variables={
            "APIM_MCP_URL": mcp_url,
            "APIM_SUBSCRIPTION_KEY": "${{connections." + connection + ".credentials.key}}",
        },
    )


def wait_for_active(project: AIProjectClient, name: str, version: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = project.agents.get_version(agent_name=name, agent_version=version)
        status = state["status"]
        print(f"Version {version}: {status}", flush=True)
        if status == "active":
            return
        if status == "failed":
            raise RuntimeError(f"Provisioning failed: {state.get('error')}")
        time.sleep(min(5, max(0, deadline - time.monotonic())))
    raise TimeoutError("Provisioning did not reach active in time; inspect the version before retrying.")


def deploy(zip_path: Path, name: str, timeout: float) -> None:
    endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"].rstrip("/")
    parsed = urlsplit(endpoint)
    if (
        parsed.scheme != "https" or not parsed.hostname
        or parsed.username or parsed.password or parsed.query or parsed.fragment
        or not re.fullmatch(r"/api/projects/[^/]+", parsed.path)
    ):
        raise ValueError("FOUNDRY_PROJECT_ENDPOINT must be https://<account>/api/projects/<project>.")
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", name):
        raise ValueError("Agent name must be 1-63 alphanumeric/hyphen characters, starting and ending alphanumeric.")
    if timeout <= 0:
        raise ValueError("Timeout must be positive.")
    definition = deployment_definition(os.environ["APIM_MCP_URL"], os.environ["APIM_KEY_CONNECTION_NAME"])
    if zip_path.stat().st_size > 250 * 1024 * 1024:
        raise ValueError("ZIP exceeds the Foundry upload limit.")
    with zipfile.ZipFile(zip_path) as archive:
        names = archive.namelist()
        if not {"main.py", "requirements.txt"}.issubset(names) or not any(name.startswith("packages/") for name in names):
            raise ValueError("Expected a flat ZIP with main.py, requirements.txt, and bundled packages/.")
        if archive.testzip() is not None:
            raise ValueError("ZIP integrity check failed.")
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    with DefaultAzureCredential() as credential, AIProjectClient(endpoint=endpoint, credential=credential) as project:
        with zip_path.open("rb") as code:
            created = project.agents.create_version_from_code(
                agent_name=name,
                definition=definition,
                code=code,
                code_zip_sha256=digest,
                description="Model-free APIM Echo MCP diagnostic; ZIP source with bundled dependencies.",
            )
        print(f"Created version {created.version}; SHA256={digest}")
        wait_for_active(project, name, created.version, timeout)
    print("Active does not prove MCP connectivity. Invoke the agent from an approved network.")
    print(f"POST {endpoint}/agents/{name}/endpoint/protocols/invocations?api-version=v1")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upload a bundled ZIP to an existing Foundry project; creates no other resources.")
    parser.add_argument("zip_path", type=Path)
    parser.add_argument("--name", default="echo-mcp-connectivity")
    parser.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args()
    deploy(args.zip_path, args.name, args.timeout)
