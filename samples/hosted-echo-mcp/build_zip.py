import argparse
import hashlib
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
MAX_ZIP_BYTES = 250 * 1024 * 1024


def build(output: Path) -> None:
    if output.exists():
        raise FileExistsError(f"Refusing to overwrite {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="hosted-echo-mcp-") as staging:
        packages = Path(staging) / "packages"
        subprocess.run(
            [
                sys.executable, "-m", "pip", "install", "--quiet", "--no-compile",
                "-r", str(SOURCE / "requirements.txt"),
                "--target", str(packages),
                "--platform", "manylinux2014_x86_64",
                "--python-version", "3.13",
                "--implementation", "cp",
                "--only-binary=:all:",
            ],
            check=True,
        )
        with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
            for name in ("main.py", "requirements.txt"):
                archive.write(SOURCE / name, name)
            for path in sorted(packages.rglob("*")):
                if not path.is_file() or "__pycache__" in path.parts:
                    continue
                if path.suffix.lower() in (".pyd", ".dll", ".whl"):
                    raise ValueError(f"Unexpected non-extracted/Linux dependency: {path.name}")
                archive.write(path, "packages/" + path.relative_to(packages).as_posix())
    if output.stat().st_size > MAX_ZIP_BYTES:
        raise ValueError("ZIP exceeds the Foundry 250 MiB upload limit.")
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("ZIP integrity check failed.")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".zip.sha256").write_text(f"{digest}  {output.name}\n", encoding="ascii")
    print(f"ZIP: {output}")
    print(f"Size: {output.stat().st_size / 1024 / 1024:.1f} MiB")
    print(f"SHA256: {digest}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bundle Linux Python 3.13 dependencies for Foundry ZIP deployment.")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    parser.add_argument("--output", type=Path, default=SOURCE.parents[1] / "tmp" / f"hosted-echo-mcp_{stamp}.zip")
    build(parser.parse_args().output.resolve())
