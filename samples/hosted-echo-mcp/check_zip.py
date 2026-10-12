import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def check(zip_path: Path) -> None:
    if sys.version_info[:2] != (3, 13):
        raise RuntimeError("Use Python 3.13 to verify the target runtime.")
    with tempfile.TemporaryDirectory(prefix="echo-mcp-startup-") as staging:
        root = Path(staging)
        with zipfile.ZipFile(zip_path) as archive:
            names = archive.namelist()
            if not {"main.py", "requirements.txt"}.issubset(names):
                raise ValueError("Missing root-level entry point or requirements.")
            for name in names:
                path = Path(name)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("Unsafe archive path.")
                if name not in ("main.py", "requirements.txt") and not name.startswith("packages/"):
                    raise ValueError(f"Unexpected archive file: {name}")
                if path.suffix.lower() in (".pyd", ".dll", ".whl"):
                    raise ValueError("Non-Linux or unextracted dependency found.")
            archive.extractall(root)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        env = dict(os.environ, PORT=str(port), OTEL_SDK_DISABLED="true")
        env.pop("APIM_MCP_URL", None)
        env.pop("APIM_SUBSCRIPTION_KEY", None)
        with (root / "startup.log").open("w+") as log:
            process = subprocess.Popen(
                [sys.executable, "-I", "main.py"], cwd=root, env=env, stdout=log, stderr=log,
            )
            try:
                deadline = time.monotonic() + 30
                while True:
                    if process.poll() is not None or time.monotonic() > deadline:
                        log.seek(0)
                        raise RuntimeError(f"Bundled runtime failed to start:\n{log.read()}")
                    try:
                        with urlopen(f"http://127.0.0.1:{port}/readiness", timeout=1) as response:
                            if response.status == 200:
                                break
                    except URLError:
                        time.sleep(0.1)
                request = Request(
                    f"http://127.0.0.1:{port}/invocations",
                    data=b'{"action":"list"}', headers={"Content-Type": "application/json"},
                )
                try:
                    urlopen(request, timeout=5).close()
                    raise AssertionError("Missing runtime configuration must fail.")
                except HTTPError as error:
                    body = json.loads(error.read())
                    if error.code != 500 or body.get("error") != "configuration_error":
                        raise AssertionError(f"Unexpected diagnostic response: {error.code} {body}")
                print("PASS: extracted bundled Python 3.13 startup, readiness, and fail-closed configuration.")
                print("No private MCP endpoint was contacted.")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Offline startup check of the actual bundled ZIP.")
    parser.add_argument("zip_path", type=Path)
    check(parser.parse_args().zip_path)
