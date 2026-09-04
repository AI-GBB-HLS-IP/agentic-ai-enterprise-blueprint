#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  set -- "."
fi

python3 - "$@" <<'PY'
import os
import re
import sys

ALLOWED_CIDRS = {
    "10.0.0.0/16",
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
    "10.0.4.0/24",
    "10.0.5.0/24",
    "10.0.6.0/26",
}

BAD_PATTERNS = [
    (re.compile(r"(?i)\b(?:customer|tenant|organization)\s*[:=]\s*\S+"), "customer/tenant identifier label"),
    (re.compile(r"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"), "email address"),
    (re.compile(r"(?i)(?:/subscriptions/|subscription\s*[:=]\s*)[0-9a-f-]{8,}"), "subscription or resource ID"),
    (re.compile(r"(?i)/(?:home|Users|mnt)/[A-Za-z0-9_./\\-]+"), "absolute local path"),
    (re.compile(r"(?i)C:\\Users\\[A-Za-z0-9_. -]+"), "Windows user path"),
    (re.compile(r"(?i)\b(?:subscriptionId|tenantId)\s*[:=]\s*['\"]?(?:[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})['\"]?"), "raw identifier"),
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}\b"), "CIDR range"),
]

ALLOWED_SNIPPETS = {
    "example.com",
    "generic-model-sku-a",
    "generic-model-sku-b",
    "policyInputs",
    "publicNetworkAccessDisabled",
    "localAuthDisabled",
    "allowedModelSkus",
    "vnet-agent-factory-poc",
    "nsg-apim",
    "nsg-compute",
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.azure-api.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.blob.core.windows.net",
    "privatelink.database.windows.net",
    "AzureBastionSubnet",
}


def iter_targets(paths):
    for target in paths:
        if os.path.isdir(target):
            for root, dirnames, filenames in os.walk(target):
                dirnames[:] = [d for d in dirnames if d not in {".git", "node_modules", ".venv", "venv", "dist", "build"}]
                for filename in filenames:
                    yield os.path.join(root, filename)
        elif os.path.isfile(target):
            yield target
        else:
            raise FileNotFoundError(f"Path not found: {target}")


def scan_content(content):
    hits = []
    for pattern, label in BAD_PATTERNS:
        for match in pattern.finditer(content):
            snippet = match.group(0)
            if snippet.lower() in {"example.com", "https://example.com"}:
                continue
            if snippet in ALLOWED_SNIPPETS:
                continue
            if snippet in ALLOWED_CIDRS:
                continue
            if re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}", snippet):
                if snippet not in ALLOWED_CIDRS:
                    hits.append((snippet, "CIDR range"))
                    continue
            hits.append((snippet, label))
    return hits

failures = []
for target in sys.argv[1:]:
    try:
        for filename in iter_targets([target]):
            try:
                with open(filename, "r", encoding="utf-8", errors="ignore") as handle:
                    content = handle.read()
            except OSError:
                continue
            hits = scan_content(content)
            if hits:
                failures.append((filename, hits))
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)

if failures:
    print("Confidentiality validation failed.", file=sys.stderr)
    for filename, hits in failures:
        print(f"- {filename}", file=sys.stderr)
        for snippet, label in hits[:5]:
            print(f"  - {label}: {snippet[:160]}", file=sys.stderr)
    raise SystemExit(1)

print("Confidentiality scan passed.")
PY
