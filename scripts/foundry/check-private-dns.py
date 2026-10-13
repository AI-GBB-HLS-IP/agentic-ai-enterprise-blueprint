#!/usr/bin/env python3
"""Read-only nslookup diagnostic for Foundry's private dependency hostnames."""

import ipaddress
import os
import re
import shutil
import subprocess
import sys


PRIVATE_NETWORKS = tuple(
    ipaddress.ip_network(cidr)
    for cidr in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "fc00::/7")
)


def env(name):
    return os.environ.get(name, "").strip()


def dns_name(value):
    return (
        len(value) <= 253
        and all(re.fullmatch(r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?", label)
                for label in value.split("."))
    )


def answer_details(output, expected_name):
    addresses = []
    answer_started = False
    private_link = False
    expected = re.compile(r"(?<![\w.-])" + re.escape(expected_name) + r"\.?(?![\w.-])", re.I)
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("Server:"):
            answer_started = False
        if line.startswith(("Name:", "Non-authoritative answer:", "Authoritative answer:")) or "canonical name =" in line:
            answer_started = True
        if not answer_started:
            continue
        private_link = private_link or bool(expected.search(line))
        match = re.match(r"Address(?:es)?:\s*(.*)", line)
        candidate = match.group(1) if match else line
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if address not in addresses:
            addresses.append(address)
    return addresses, private_link


def non_public(address):
    return any(address.version == network.version and address in network for network in PRIVATE_NETWORKS)


def main():
    services = (
        ("Foundry service plane", "FOUNDRY_ACCOUNT_NAME", "services.ai.azure.com"),
        ("Foundry inference", "FOUNDRY_ACCOUNT_NAME", "openai.azure.com"),
        ("Cognitive Services", "FOUNDRY_ACCOUNT_NAME", "cognitiveservices.azure.com"),
        ("Cosmos DB", "COSMOS_ACCOUNT_NAME", "documents.azure.com"),
        ("Blob Storage", "STORAGE_ACCOUNT_NAME", "blob.core.windows.net"),
        ("AI Search", "SEARCH_SERVICE_NAME", "search.windows.net"),
    )
    required = sorted({variable for _, variable, _ in services})
    for variable in required + ["KEY_VAULT_NAME"]:
        value = env(variable)
        if not value and variable in required:
            print(f"ERROR: export {variable} before running this script.", file=sys.stderr)
            return 2
        if value and (not dns_name(value) or "." in value):
            print(f"ERROR: {variable} must be a resource name, not a URL or hostname.", file=sys.stderr)
            return 2
    resolver = env("DNS_SERVER")
    if resolver and not dns_name(resolver):
        print("ERROR: DNS_SERVER must be an IPv4 address or DNS hostname.", file=sys.stderr)
        return 2
    lookups = [(label, f"{env(variable)}.{suffix}") for label, variable, suffix in services]
    if env("KEY_VAULT_NAME"):
        lookups.append(("Key Vault", f"{env('KEY_VAULT_NAME')}.vault.azure.net"))
    regional = env("COSMOS_REGIONAL_HOSTNAMES").split()
    for hostname in regional:
        if not dns_name(hostname) or not hostname.lower().endswith(".documents.azure.com"):
            print("ERROR: COSMOS_REGIONAL_HOSTNAMES must contain space-separated Cosmos DNS names.", file=sys.stderr)
            return 2
        lookups.append(("Cosmos regional endpoint", hostname))
    if not shutil.which("nslookup"):
        print("ERROR: nslookup is required; install your operating system's DNS utilities.", file=sys.stderr)
        return 2
    print("DNS-only diagnostic from this machine; no Azure login or configuration changes.")
    print("PASS requires the expected private-link name and only RFC1918/RFC6598/ULA answer IPs.")
    print("RFC6598 (100.64.0.0/10) is shared address space, not RFC1918.")
    print("Results do not prove expected endpoint ownership, routing, TLS, RBAC, or agent access.\n")
    counts = {"PASS": 0, "WARN": 0, "FAIL": 0}
    for label, hostname in lookups:
        stem, _, suffix = hostname.partition(".")
        expected = f"{stem}.privatelink.{suffix}"
        if suffix == "vault.azure.net":
            expected = f"{stem}.privatelink.vaultcore.azure.net"
        print(f"=== {label}: https://{hostname} ===", flush=True)
        command = ["nslookup", "-timeout=5", "-retry=1", hostname]
        if resolver:
            command.append(resolver)
        try:
            result = subprocess.run(
                command, capture_output=True, text=True, timeout=15, check=False,
                env={**os.environ, "LC_ALL": "C"},
            )
        except subprocess.TimeoutExpired:
            print("FAIL: nslookup exceeded 15 seconds.\n")
            counts["FAIL"] += 1
            continue
        except OSError as error:
            print(f"ERROR: cannot execute nslookup: {error}", file=sys.stderr)
            return 2
        print(result.stdout.strip())
        if result.stderr:
            print(result.stderr.strip())
        addresses, private_link = answer_details(result.stdout, expected)
        if result.returncode != 0 or not addresses:
            status, reason = "FAIL", f"lookup failed or no answer IPs (exit {result.returncode})"
        elif not all(non_public(address) for address in addresses):
            status, reason = "FAIL", "answer includes public or other non-private/shared addresses"
        elif not private_link:
            status, reason = "WARN", "non-public answer, but expected private-link name was not observed (split DNS is possible)"
        else:
            status, reason = "PASS", "expected private-link name and non-public answer IPs observed"
        print(f"{status}: {reason}\n")
        counts[status] += 1
    print(f"SUMMARY: {counts['PASS']} passed, {counts['WARN']} warnings, {counts['FAIL']} failed")
    print("Optional Key Vault: " + ("checked" if env("KEY_VAULT_NAME") else "not supplied; skipped"))
    if not regional:
        print("Cosmos regional names: not supplied; retrieve all names from the private endpoint's DNS configuration.")
    print("APIM/MCP, registry, authentication egress, and other optional services are outside this diagnostic.")
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
