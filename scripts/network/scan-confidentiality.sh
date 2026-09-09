#!/usr/bin/env bash
set -euo pipefail

# Repository confidentiality gate (T014).
#
# Fails closed on concrete discovery-derived values that must never be committed:
# real subscription/tenant GUIDs, resolved ARM resource IDs, real email addresses,
# absolute home directory paths, and private address ranges outside the blueprint's
# own approved address plan.
#
# Design notes:
#   * Vocabulary is not disclosure. Words such as "customer", "tenant", or
#     "organization" in prose are never flagged.
#   * Public Microsoft constants (built-in role definition IDs, first-party
#     application IDs, permission scope IDs) are not secrets. A GUID is reported
#     only when its context identifies it as a subscription or tenant reference.
#   * Documented fictional domains and placeholder tokens are permitted.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

targets=("$@")

if [[ ${#targets[@]} -eq 0 ]]; then
  # Default to tracked files only; untracked local discovery output is ignored by design.
  cd "$REPO_ROOT"
  mapfile -t targets < <(git ls-files)
  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "No tracked files to scan." >&2
    exit 1
  fi
fi

python3 - "${targets[@]}" <<'PY'
import ipaddress
import os
import re
import sys

# The blueprint owns 10.0.0.0/16; any prefix inside it is an approved constant.
BLUEPRINT_SUPERNET = ipaddress.ip_network("10.0.0.0/16")

# RFC 1918 block declarations used when describing address space in general.
RFC1918_BLOCKS = {"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"}

# Documentation-only domains: RFC 2606 plus Microsoft's fictional sample companies.
ALLOWED_EMAIL_DOMAIN_PARTS = (
    "example.com",
    "example.org",
    "example.net",
    "contoso.com",
    "fabrikam.com",
    "adatum.com",
    "company.com",
    "users.noreply.github.com",
)

PLACEHOLDER_TOKENS = ("<", ">", "{", "}", "...", "$", "%")

GUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)

# A GUID is disclosure only when it is presented as a subscription or tenant value.
GUID_DISCLOSURE_CONTEXT = re.compile(r"subscription|tenant|/subscriptions/", re.IGNORECASE)

# Public Microsoft constants: built-in role definition IDs and first-party app IDs.
GUID_PUBLIC_CONSTANT_CONTEXT = re.compile(
    r"roleDefinition|roleAssignment|appId|applicationId|servicePrincipalType|permission|scopeId",
    re.IGNORECASE,
)

ARM_ID_RE = re.compile(
    r"/subscriptions/[^/\s\"'`)]+/resourceGroups/[^/\s\"'`)]+", re.IGNORECASE
)
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
HOME_PATH_RE = re.compile(r"(?:/home/|/Users/)[A-Za-z0-9._-]+/")
WIN_PATH_RE = re.compile(r"[A-Za-z]:\\Users\\[A-Za-z0-9._ -]+")
CIDR_RE = re.compile(r"\b(?:10|172|192)\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}\b")

SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "dist", "build", ".terraform"}
SKIP_SUFFIXES = (".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".ico", ".woff", ".woff2")


def is_placeholder_guid(value):
    return value.lower() == "00000000-0000-0000-0000-000000000000"


def cidr_allowed(value):
    if value in RFC1918_BLOCKS:
        return True
    try:
        network = ipaddress.ip_network(value, strict=False)
    except ValueError:
        return False

    # Only treat *private* address space as disclosure; public/test ranges are allowed.
    if not network.is_private:
        return True

    return network.subnet_of(BLUEPRINT_SUPERNET)


def check_line(line):
    findings = []

    for match in GUID_RE.finditer(line):
        value = match.group(0)
        if is_placeholder_guid(value):
            continue
        if GUID_PUBLIC_CONSTANT_CONTEXT.search(line):
            continue
        if not GUID_DISCLOSURE_CONTEXT.search(line):
            continue
        findings.append(("subscription or tenant GUID", value))

    for match in ARM_ID_RE.finditer(line):
        value = match.group(0)
        if any(token in value for token in PLACEHOLDER_TOKENS):
            continue
        if GUID_RE.search(value) and is_placeholder_guid(GUID_RE.search(value).group(0)):
            continue
        findings.append(("resolved ARM resource ID", value))

    for match in EMAIL_RE.finditer(line):
        value = match.group(0)
        if value.lower().endswith(ALLOWED_EMAIL_DOMAIN_PARTS):
            continue
        findings.append(("email address", value))

    for match in HOME_PATH_RE.finditer(line):
        findings.append(("absolute home directory path", match.group(0)))

    for match in WIN_PATH_RE.finditer(line):
        findings.append(("Windows user path", match.group(0)))

    for match in CIDR_RE.finditer(line):
        value = match.group(0)
        if cidr_allowed(value):
            continue
        findings.append(("non-blueprint private address range", value))

    return findings


def iter_files(paths):
    for target in paths:
        if os.path.isdir(target):
            for root, dirnames, filenames in os.walk(target):
                dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
                for filename in sorted(filenames):
                    yield os.path.join(root, filename)
        elif os.path.isfile(target):
            yield target


def scan(path):
    if path.lower().endswith(SKIP_SUFFIXES):
        return []
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return []

    hits = []
    for number, line in enumerate(lines, start=1):
        for label, value in check_line(line):
            hits.append((number, label, value))
    return hits


failures = []
for path in iter_files(sys.argv[1:]):
    hits = scan(path)
    if hits:
        failures.append((path, hits))

if failures:
    print("Confidentiality validation failed.", file=sys.stderr)
    for path, hits in failures:
        print(f"- {path}", file=sys.stderr)
        for number, label, value in hits[:10]:
            print(f"  - line {number}: {label}: {value[:120]}", file=sys.stderr)
    raise SystemExit(1)

print("Confidentiality scan passed.")
PY
