import asyncio
import logging
import os
import sys
from pathlib import Path
from urllib.parse import urlsplit
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parent / "packages"))

import anyio
import httpx
from azure.ai.agentserver.invocations import InvocationAgentServerHost
from jsonschema import Draft202012Validator
from mcp import ClientSession, McpError
from mcp.client.streamable_http import streamable_http_client
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from starlette.requests import Request
from starlette.responses import JSONResponse

logger = logging.getLogger("echo_mcp")
TIMEOUT_SECONDS = 45
MAX_REQUEST_BYTES = 65536


class Invocation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: str = Field(pattern="^(list|call)$")
    tool: str | None = Field(default=None, min_length=1)
    arguments: dict = Field(default_factory=dict)


class DiagnosticError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code


def configuration() -> tuple[str, str]:
    url = os.environ.get("APIM_MCP_URL", "")
    parsed = urlsplit(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
    ):
        raise DiagnosticError(
            500, "configuration_error",
            "Set APIM_MCP_URL to the exact HTTPS MCP endpoint without credentials or query parameters.",
        )
    key = os.environ.get("APIM_SUBSCRIPTION_KEY", "")
    if not key or key.startswith("${{"):
        raise DiagnosticError(
            500, "configuration_error",
            "APIM_SUBSCRIPTION_KEY is missing or its Foundry connection reference is unresolved.",
        )
    return url, key


async def run_mcp(
    invocation: Invocation,
    url: str,
    key: str,
    correlation_id: str,
    transport: httpx.AsyncBaseTransport | None = None,
) -> dict:
    async with httpx.AsyncClient(
        headers={
            "Ocp-Apim-Subscription-Key": key,
            "x-correlation-id": correlation_id,
        },
        timeout=httpx.Timeout(15, read=30),
        follow_redirects=False,
        transport=transport,
    ) as client:
        async with streamable_http_client(url, http_client=client) as streams:
            async with ClientSession(streams[0], streams[1]) as session:
                initialized = await session.initialize()
                tools = []
                cursor = None
                seen_cursors = set()
                while True:
                    page = await session.list_tools(cursor=cursor)
                    tools.extend(page.tools)
                    cursor = page.nextCursor
                    if not cursor:
                        break
                    if cursor in seen_cursors:
                        raise DiagnosticError(502, "invalid_tool_listing", "MCP returned a repeated pagination cursor.")
                    seen_cursors.add(cursor)

                output = {
                    "status": "pass",
                    "correlation_id": correlation_id,
                    "protocol_version": initialized.protocolVersion,
                    "tools": [
                        {"name": tool.name, "input_schema": tool.inputSchema}
                        for tool in tools
                    ],
                }
                if invocation.action == "call":
                    selected = next((tool for tool in tools if tool.name == invocation.tool), None)
                    if selected is None:
                        raise DiagnosticError(400, "unknown_tool", "Choose an exact tool name from the list response.")
                    if not Draft202012Validator(selected.inputSchema).is_valid(invocation.arguments):
                        raise DiagnosticError(400, "invalid_arguments", "Arguments do not match the selected tool input schema.")
                    result = await session.call_tool(selected.name, invocation.arguments)
                    if result.isError:
                        raise DiagnosticError(502, "tool_error", "The MCP tool reported an execution error.")
                    output["tool"] = selected.name
                    output["result"] = result.model_dump(mode="json", by_alias=True, exclude_none=True)
                return output


def error_leaves(error: Exception) -> list[Exception]:
    if isinstance(error, ExceptionGroup):
        return [leaf for child in error.exceptions for leaf in error_leaves(child)]
    return [error]


def upstream_error(error: Exception) -> DiagnosticError:
    leaves = error_leaves(error)
    known = (DiagnosticError, httpx.HTTPError, McpError, TimeoutError, anyio.EndOfStream, anyio.BrokenResourceError)
    if any(not isinstance(leaf, known) for leaf in leaves):
        raise error
    for leaf in leaves:
        if isinstance(leaf, DiagnosticError):
            return leaf
        if isinstance(leaf, httpx.HTTPStatusError):
            status = leaf.response.status_code
            return DiagnosticError(
                502, "apim_http_error",
                f"APIM returned HTTP {status}; check subscription, policy, route, and MCP configuration.",
            )
    if any(isinstance(leaf, (TimeoutError, httpx.TimeoutException)) for leaf in leaves):
        return DiagnosticError(504, "mcp_timeout", "MCP did not complete within the timeout.")
    if any(isinstance(leaf, httpx.ConnectError) for leaf in leaves):
        return DiagnosticError(502, "mcp_connection_error", "Cannot connect to APIM; check private DNS, routing, firewall, and TLS trust.")
    return DiagnosticError(502, "mcp_protocol_error", "MCP communication failed; check transport compatibility and APIM diagnostics.")


app = InvocationAgentServerHost()


@app.invoke_handler
async def invoke(request: Request):
    correlation_id = str(uuid4())
    try:
        body = await request.body()
        if len(body) > MAX_REQUEST_BYTES:
            raise DiagnosticError(413, "request_too_large", "Request exceeds 64 KiB.")
        try:
            invocation = Invocation.model_validate_json(body)
        except ValidationError:
            raise DiagnosticError(400, "invalid_request", 'Send {"action":"list"} or {"action":"call","tool":"exact-name","arguments":{}}.') from None
        if invocation.action == "call" and not invocation.tool:
            raise DiagnosticError(400, "missing_tool", "The call action requires an explicit tool name.")
        if invocation.action == "list" and (invocation.tool or invocation.arguments):
            raise DiagnosticError(400, "invalid_request", "The list action does not accept a tool or arguments.")
        url, key = configuration()
        try:
            async with asyncio.timeout(TIMEOUT_SECONDS):
                output = await run_mcp(invocation, url, key, correlation_id)
        except (httpx.HTTPError, McpError, TimeoutError, anyio.EndOfStream, anyio.BrokenResourceError, ExceptionGroup) as error:
            raise upstream_error(error) from None
    except DiagnosticError as error:
        logger.warning("MCP diagnostic failed correlation_id=%s code=%s", correlation_id, error.code)
        return JSONResponse(
            {"status": "fail", "correlation_id": correlation_id, "error": error.code, "message": str(error)},
            status_code=error.status,
        )
    logger.info("MCP diagnostic passed correlation_id=%s action=%s", correlation_id, invocation.action)
    return JSONResponse(output)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    app.run()
