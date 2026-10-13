import asyncio
import hashlib
import json
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import AsyncMock, patch

os.environ["OTEL_SDK_DISABLED"] = "true"

import httpx
import main
import deploy as deploy_module
from azure.core.credentials import AccessToken
from azure.core.exceptions import HttpResponseError, ResourceNotFoundError, ServiceRequestError
from deploy import deployment_definition, wait_for_active

URL = "https://gateway.example.com/echo-mcp/mcp"
KEY = "test-only-not-a-real-key"
SCHEMA = {
    "type": "object",
    "properties": {"message": {"type": "string"}},
    "required": ["message"],
    "additionalProperties": False,
}


class McpTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.methods = []
        self.mode = "json"
        self.http_status = 200
        self.tool_error = False
        self.pages = False

    async def mock_server(self, request):
        self.assertEqual(request.headers["Ocp-Apim-Subscription-Key"], KEY)
        self.assertEqual(request.headers["x-correlation-id"], "test-correlation")
        self.assertEqual(str(request.url), URL)
        if self.http_status != 200:
            return httpx.Response(self.http_status, json={"message": "denied"})
        data = json.loads(request.content)
        method = data["method"]
        self.methods.append(method)
        if method == "notifications/initialized":
            return httpx.Response(202)
        if method == "initialize":
            result = {
                "protocolVersion": data["params"]["protocolVersion"],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "mock-echo", "version": "1"},
            }
        elif method == "tools/list":
            result = {"tools": [{"name": "echo", "inputSchema": SCHEMA}]}
            if self.pages and not data.get("params", {}).get("cursor"):
                result = {"tools": [], "nextCursor": "page-two"}
        elif method == "tools/call":
            self.assertEqual(data["params"]["name"], "echo")
            result = {
                "content": [{"type": "text", "text": data["params"]["arguments"]["message"]}],
                "isError": self.tool_error,
            }
        else:
            self.fail(f"Unexpected MCP method {method}")
        payload = {"jsonrpc": "2.0", "id": data["id"], "result": result}
        if self.mode == "sse":
            return httpx.Response(200, text=f"event: message\ndata: {json.dumps(payload)}\n\n", headers={"Content-Type": "text/event-stream"})
        return httpx.Response(200, json=payload)

    async def run_diagnostic(self, **kwargs):
        async with asyncio.timeout(3):
            return await main.run_mcp(
                main.Invocation(**kwargs), URL, KEY, "test-correlation",
                transport=httpx.MockTransport(self.mock_server),
            )

    async def test_discover_tools_without_model(self):
        result = await self.run_diagnostic(action="list")
        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["tools"][0]["name"], "echo")
        self.assertEqual(self.methods, ["initialize", "notifications/initialized", "tools/list"])

    async def test_call_echo(self):
        result = await self.run_diagnostic(action="call", tool="echo", arguments={"message": "hello"})
        self.assertEqual(result["result"]["content"][0]["text"], "hello")
        self.assertIn("tools/call", self.methods)

    async def test_sse_response(self):
        self.mode = "sse"
        result = await self.run_diagnostic(action="call", tool="echo", arguments={"message": "hello"})
        self.assertEqual(result["result"]["content"][0]["text"], "hello")

    async def test_paginated_discovery(self):
        self.pages = True
        result = await self.run_diagnostic(action="list")
        self.assertEqual(len(result["tools"]), 1)
        self.assertEqual(self.methods.count("tools/list"), 2)

    async def test_unknown_tool_never_called(self):
        with self.assertRaises(ExceptionGroup) as caught:
            await self.run_diagnostic(action="call", tool="missing")
        self.assertEqual(main.upstream_error(caught.exception).code, "unknown_tool")
        self.assertNotIn("tools/call", self.methods)

    async def test_invalid_arguments_never_called(self):
        with self.assertRaises(ExceptionGroup) as caught:
            await self.run_diagnostic(action="call", tool="echo", arguments={"message": 42})
        self.assertEqual(main.upstream_error(caught.exception).code, "invalid_arguments")
        self.assertNotIn("tools/call", self.methods)

    async def test_tool_error_is_failure(self):
        self.tool_error = True
        with self.assertRaises(ExceptionGroup) as caught:
            await self.run_diagnostic(action="call", tool="echo", arguments={"message": "hello"})
        self.assertEqual(main.upstream_error(caught.exception).code, "tool_error")

    async def test_apim_auth_failure(self):
        self.http_status = 401
        with self.assertRaises(ExceptionGroup) as caught:
            await self.run_diagnostic(action="list")
        error = main.upstream_error(caught.exception)
        self.assertEqual(error.code, "apim_http_error")
        self.assertIn("401", str(error))

    async def test_timeout_cancels_real_mcp_transport(self):
        async def delayed(request):
            await asyncio.sleep(1)
        with self.assertRaises(TimeoutError):
            async with asyncio.timeout(0.01):
                await main.run_mcp(
                    main.Invocation(action="list"), URL, KEY, "test-correlation",
                    transport=httpx.MockTransport(delayed),
                )


class HandlerTests(unittest.IsolatedAsyncioTestCase):
    async def send(self, payload, mock=None):
        with patch.dict(os.environ, {"APIM_MCP_URL": URL, "APIM_SUBSCRIPTION_KEY": KEY}):
            with patch.object(main, "run_mcp", mock or AsyncMock(return_value={"status": "pass"})):
                async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url="http://localhost") as client:
                    return await client.post("/invocations", json=payload)

    async def test_handler_and_readiness(self):
        response = await self.send({"action": "list"})
        self.assertEqual(response.status_code, 200)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url="http://localhost") as client:
            self.assertEqual((await client.get("/readiness")).status_code, 200)

    async def test_invalid_request_logged(self):
        for payload in ({"action": "invalid"}, {}, "text", {"action": "list", "url": URL}, {"action": "list", "tool": "echo"}):
            with self.assertLogs("echo_mcp", level="WARNING"):
                response = await self.send(payload)
            self.assertEqual(response.status_code, 400)
            self.assertEqual(response.json()["status"], "fail")

    async def test_missing_tool(self):
        response = await self.send({"action": "call"})
        self.assertEqual(response.json()["error"], "missing_tool")

    async def test_dns_failure(self):
        response = await self.send({"action": "list"}, AsyncMock(side_effect=httpx.ConnectError("private DNS unavailable")))
        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.json()["error"], "mcp_connection_error")
        self.assertNotIn(KEY, response.text)

    async def test_timeout(self):
        async def delayed(*args, **kwargs):
            await asyncio.sleep(1)
        with patch.object(main, "TIMEOUT_SECONDS", 0.01):
            response = await self.send({"action": "list"}, AsyncMock(side_effect=delayed))
        self.assertEqual(response.status_code, 504)
        self.assertEqual(response.json()["error"], "mcp_timeout")

    async def test_malformed_json(self):
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url="http://localhost") as client:
            response = await client.post("/invocations", content=b"{")
        self.assertEqual(response.status_code, 400)

    async def test_large_request(self):
        response = await self.send({"action": "list", "padding": "x" * main.MAX_REQUEST_BYTES})
        self.assertEqual(response.status_code, 413)


class ConfigurationTests(unittest.TestCase):
    def test_missing_key(self):
        for key in ("", "${{connections.echo.credentials.key}}"):
            with patch.dict(os.environ, {"APIM_MCP_URL": URL, "APIM_SUBSCRIPTION_KEY": key}):
                with self.assertRaises(main.DiagnosticError):
                    main.configuration()

    def test_url_credentials_and_plain_http_rejected(self):
        for url in ("http://gateway.example.com/mcp", "https://user:secret@gateway.example.com/mcp", URL + "?key=secret"):
            with patch.dict(os.environ, {"APIM_MCP_URL": url, "APIM_SUBSCRIPTION_KEY": KEY}):
                with self.assertRaises(main.DiagnosticError):
                    main.configuration()

    def test_unknown_exception_not_masked(self):
        with self.assertRaises(ExceptionGroup) as caught:
            main.upstream_error(ExceptionGroup("unexpected", [TypeError("bug")]))
        self.assertIsInstance(caught.exception.exceptions[0], TypeError)

    def test_deployment_uses_zip_and_connection_reference(self):
        definition = deployment_definition(URL, "echo-mcp")
        self.assertEqual(definition.code_configuration.runtime, "python_3_13")
        self.assertEqual(definition.code_configuration.dependency_resolution, "bundled")
        self.assertEqual(definition.protocol_versions[0].protocol, "invocations")
        self.assertEqual(definition.environment_variables["APIM_SUBSCRIPTION_KEY"], "${{connections.echo-mcp.credentials.key}}")
        self.assertIsNone(definition.container_configuration)

    def test_deployment_passes_public_sdk_arguments(self):
        from unittest.mock import MagicMock

        with tempfile.TemporaryDirectory() as directory:
            zip_path = os.path.join(directory, "agent.zip")
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("main.py", "")
                archive.writestr("requirements.txt", "")
                archive.writestr("packages/runtime.py", "")
            project = MagicMock()
            project.__enter__.return_value = project
            credential = MagicMock()
            credential.__enter__.return_value = credential
            with (
                patch.dict(os.environ, {
                    "FOUNDRY_PROJECT_ENDPOINT": "https://account.services.ai.azure.com/api/projects/project",
                    "APIM_MCP_URL": URL,
                    "APIM_KEY_CONNECTION_NAME": "echo-mcp",
                }),
                patch.object(deploy_module, "DefaultAzureCredential", return_value=credential),
                patch.object(deploy_module, "AIProjectClient", return_value=project),
                patch.object(deploy_module, "wait_for_active"),
            ):
                deploy_module.deploy(Path(zip_path), "echo-agent", 1)

            project.connections.get.assert_called_once_with(name="echo-mcp", include_credentials=False)
            self.assertEqual(project.method_calls[0][0], "connections.get")
            kwargs = project.agents.create_version_from_code.call_args.kwargs
            self.assertNotIn("content", kwargs)
            self.assertEqual(kwargs["description"], "Model-free APIM Echo MCP diagnostic; ZIP source with bundled dependencies.")
            self.assertEqual(kwargs["definition"].code_configuration.runtime, "python_3_13")
            self.assertEqual(kwargs["code"].name, zip_path)

    def test_real_sdk_serializes_zip_and_polls_offline(self):
        from email import policy
        from email.parser import BytesParser
        from io import BytesIO
        from unittest.mock import MagicMock
        import requests

        calls = []

        def send(request, **kwargs):
            calls.append(request)
            response = requests.Response()
            response.status_code = 200
            response.headers["Content-Type"] = "application/json"
            response.url = request.url
            if request.method == "GET" and "/connections/echo-mcp" in request.url:
                payload = {"name": "echo-mcp", "type": "ApiKey", "target": URL}
            elif request.method in ("POST", "GET") and "/agents/echo-agent/" in request.url:
                payload = {"name": "echo-agent", "version": "1", "status": "active"}
            else:
                self.fail(f"Unexpected SDK request: {request.method} {request.url}")
            response._content = json.dumps(payload).encode()
            response.raw = BytesIO(response._content)
            return response

        with tempfile.TemporaryDirectory() as directory:
            zip_path = Path(directory) / "agent.zip"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("main.py", "")
                archive.writestr("requirements.txt", "")
                archive.writestr("packages/runtime.py", "")
            zip_bytes = zip_path.read_bytes()
            credential = MagicMock(spec=["get_token", "__enter__", "__exit__"])
            credential.__enter__.return_value = credential
            credential.get_token.return_value = AccessToken("offline-test-token", 4102444800)
            with (
                patch.dict(os.environ, {
                    "FOUNDRY_PROJECT_ENDPOINT": "https://account.services.ai.azure.com/api/projects/project",
                    "APIM_MCP_URL": URL,
                    "APIM_KEY_CONNECTION_NAME": "echo-mcp",
                }),
                patch.object(deploy_module, "DefaultAzureCredential", return_value=credential),
                patch.object(requests.Session, "send", side_effect=send),
            ):
                deploy_module.deploy(zip_path, "echo-agent", 1)

        self.assertEqual([call.method for call in calls], ["GET", "POST", "GET"])
        upload = calls[1]
        self.assertEqual(
            upload.url,
            "https://account.services.ai.azure.com/api/projects/project/agents/echo-agent/versions?api-version=v1",
        )
        self.assertEqual(upload.headers["x-ms-code-zip-sha256"], hashlib.sha256(zip_bytes).hexdigest())
        multipart = BytesParser(policy=policy.default).parsebytes(
            b"Content-Type: " + upload.headers["Content-Type"].encode() + b"\r\n\r\n" + upload.body
        )
        parts = {part.get_param("name", header="content-disposition"): part for part in multipart.iter_parts()}
        self.assertEqual(parts["code"].get_filename(), "agent.zip")
        self.assertEqual(parts["code"].get_payload(decode=True), zip_bytes)
        metadata = json.loads(parts["metadata"].get_payload(decode=True))
        self.assertEqual(metadata["definition"], deployment_definition(URL, "echo-mcp").as_dict())
        self.assertNotIn(KEY, upload.body.decode(errors="replace"))

    def test_connection_failures_prevent_upload(self):
        from unittest.mock import MagicMock

        with tempfile.TemporaryDirectory() as directory:
            zip_path = Path(directory) / "agent.zip"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("main.py", "")
                archive.writestr("requirements.txt", "")
                archive.writestr("packages/runtime.py", "")
            for error in (
                ResourceNotFoundError("missing connection"),
                HttpResponseError("connection access denied"),
                ServiceRequestError("connection metadata unreachable"),
            ):
                with self.subTest(error=type(error).__name__):
                    project = MagicMock()
                    project.__enter__.return_value = project
                    project.connections.get.side_effect = error
                    credential = MagicMock()
                    credential.__enter__.return_value = credential
                    with (
                        patch.dict(os.environ, {
                            "FOUNDRY_PROJECT_ENDPOINT": "https://account.services.ai.azure.com/api/projects/project",
                            "APIM_MCP_URL": URL,
                            "APIM_KEY_CONNECTION_NAME": "existing-key",
                        }),
                        patch.object(deploy_module, "DefaultAzureCredential", return_value=credential),
                        patch.object(deploy_module, "AIProjectClient", return_value=project),
                        patch.object(deploy_module, "wait_for_active") as wait,
                    ):
                        expected = ValueError if isinstance(error, ResourceNotFoundError) else type(error)
                        with self.assertRaises(expected) as caught:
                            deploy_module.deploy(zip_path, "echo-agent", 1)
                    if isinstance(error, ResourceNotFoundError):
                        self.assertIn("Foundry connection 'existing-key'", str(caught.exception))
                        self.assertIn("FOUNDRY_PROJECT_ENDPOINT", str(caught.exception))
                        self.assertIn("Connected resources", str(caught.exception))
                        self.assertIs(caught.exception.__cause__, error)
                    else:
                        self.assertIs(caught.exception, error)
                    project.connections.get.assert_called_once_with(name="existing-key", include_credentials=False)
                    project.agents.create_version_from_code.assert_not_called()
                    wait.assert_not_called()

    def test_provisioning_failure_and_timeout(self):
        from unittest.mock import Mock
        project = Mock()
        project.agents.get_version.return_value = {"status": "failed", "error": {"code": "CodeError"}}
        with self.assertRaisesRegex(RuntimeError, "CodeError"):
            wait_for_active(project, "echo", "1", 1)
        with self.assertRaises(TimeoutError):
            wait_for_active(project, "echo", "1", 0)


if __name__ == "__main__":
    unittest.main()
