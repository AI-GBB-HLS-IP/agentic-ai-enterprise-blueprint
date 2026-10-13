import importlib.util
import io
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout, redirect_stderr


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/foundry/check-private-dns.py"
SPEC = importlib.util.spec_from_file_location("check_private_dns", SCRIPT)
diagnostic = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diagnostic)

ENV = {
    "FOUNDRY_ACCOUNT_NAME": "test-foundry",
    "COSMOS_ACCOUNT_NAME": "test-cosmos",
    "STORAGE_ACCOUNT_NAME": "teststorage",
    "SEARCH_SERVICE_NAME": "test-search",
}


def response(command, **kwargs):
    host = command[3]
    stem, _, suffix = host.partition(".")
    if suffix == "vault.azure.net":
        suffix = "vaultcore.azure.net"
    target = f"{stem}.privatelink.{suffix}"
    output = (
        "Server:\t10.0.0.2\nAddress:\t10.0.0.2#53\n\nNon-authoritative answer:\n"
        f"{host} canonical name = {target}.\nName:\t{target}\nAddress: 100.64.0.5\n"
    )
    return subprocess.CompletedProcess(command, 0, output, "")


class DnsDiagnosticTests(unittest.TestCase):
    def run_main(self, extra=None, lookup=response):
        output = io.StringIO()
        with patch.dict(os.environ, {**ENV, **(extra or {})}, clear=True), \
                patch.object(diagnostic.shutil, "which", return_value="/usr/bin/nslookup"), \
                patch.object(diagnostic.subprocess, "run", side_effect=lookup) as run, \
                redirect_stdout(output), redirect_stderr(output):
            code = diagnostic.main()
        return code, output.getvalue(), run

    def test_core_private_link_with_shared_space(self):
        code, output, run = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("6 passed, 0 warnings, 0 failed", output)
        self.assertEqual(run.call_count, 6)

    def test_optional_endpoints_resolver_and_crlf_inputs(self):
        code, output, run = self.run_main({
            "FOUNDRY_ACCOUNT_NAME": "test-foundry\r\n",
            "KEY_VAULT_NAME": "test-vault",
            "DNS_SERVER": "10.0.0.2",
            "COSMOS_REGIONAL_HOSTNAMES": "test-cosmos-eastus.documents.azure.com",
        })
        self.assertEqual(code, 0)
        self.assertIn("8 passed", output)
        for call in run.call_args_list:
            self.assertEqual(call.args[0][-1], "10.0.0.2")
        self.assertIn("https://test-vault.vault.azure.net", output)

    def test_answer_parsing_excludes_resolver_and_supports_windows_crlf(self):
        addresses, observed = diagnostic.answer_details(
            "Server: resolver\r\nAddress: 10.0.0.2\r\n\r\n"
            "Name: test.privatelink.documents.azure.com\r\n"
            "Addresses: 10.0.0.5\r\n          100.64.0.5\r\nAliases: test.documents.azure.com\r\n",
            "test.privatelink.documents.azure.com",
        )
        self.assertEqual([str(ip) for ip in addresses], ["10.0.0.5", "100.64.0.5"])
        self.assertTrue(observed)

    def test_cname_without_answer_is_not_success(self):
        code, output, _ = self.run_main(lookup=lambda command, **kwargs: subprocess.CompletedProcess(
            command, 0, response(command).stdout.rsplit("Address:", 1)[0], ""))
        self.assertEqual(code, 1)
        self.assertIn("0 passed, 0 warnings, 6 failed", output)

    def test_resolver_address_alone_is_not_an_answer(self):
        code, _, _ = self.run_main(lookup=lambda command, **kwargs: subprocess.CompletedProcess(
            command, 0, "Server: resolver\nAddress: 10.0.0.2\n", ""))
        self.assertEqual(code, 1)

    def test_unrelated_private_link_name_does_not_pass(self):
        code, output, _ = self.run_main(lookup=lambda command, **kwargs: subprocess.CompletedProcess(
            command, 0, "Name: unrelated.privatelink.documents.azure.com\nAddress: 10.0.0.5\n", ""))
        self.assertEqual(code, 0)
        self.assertIn("0 passed, 6 warnings, 0 failed", output)

    def test_public_and_mixed_addresses_fail(self):
        for addition in ["Address: 8.8.8.8\n", "Address: 127.0.0.1\n"]:
            with self.subTest(addition=addition):
                code, _, _ = self.run_main(lookup=lambda command, **kwargs: subprocess.CompletedProcess(
                    command, 0, response(command).stdout + addition, ""))
                self.assertEqual(code, 1)

    def test_direct_private_answer_warns(self):
        code, output, _ = self.run_main(lookup=lambda command, **kwargs: subprocess.CompletedProcess(
            command, 0, f"Name: {command[3]}\nAddress: 10.0.0.5\n", ""))
        self.assertEqual(code, 0)
        self.assertIn("0 passed, 6 warnings, 0 failed", output)

    def test_lookup_errors_and_timeouts(self):
        for lookup in [
            lambda command, **kwargs: subprocess.CompletedProcess(command, 1, "", "NXDOMAIN"),
            lambda command, **kwargs: subprocess.CompletedProcess(command, 1, response(command).stdout, "lookup error"),
        ]:
            code, output, _ = self.run_main(lookup=lookup)
            self.assertEqual(code, 1)
            self.assertIn("6 failed", output)
        code, output, _ = self.run_main(lookup=subprocess.TimeoutExpired("nslookup", 15))
        self.assertEqual(code, 1)
        self.assertIn("exceeded 15 seconds", output)

    def test_input_errors_do_not_run_lookup(self):
        for extra in [
            {"COSMOS_ACCOUNT_NAME": ""},
            {"FOUNDRY_ACCOUNT_NAME": "https://example.com"},
            {"DNS_SERVER": "-bad"},
            {"COSMOS_REGIONAL_HOSTNAMES": "https://example.com"},
        ]:
            with self.subTest(extra=extra):
                code, output, run = self.run_main(extra)
                self.assertEqual(code, 2)
                self.assertIn("ERROR:", output)
                run.assert_not_called()

    def test_address_classification(self):
        for value in ["10.0.0.1", "172.16.0.1", "192.168.0.1", "100.64.0.5", "fd00::1"]:
            self.assertTrue(diagnostic.non_public(diagnostic.ipaddress.ip_address(value)))
        for value in ["8.8.8.8", "127.0.0.1", "169.254.1.1", "100.128.0.1", "::1", "fe80::1"]:
            self.assertFalse(diagnostic.non_public(diagnostic.ipaddress.ip_address(value)))

    def test_missing_tool(self):
        with patch.dict(os.environ, ENV, clear=True), \
                patch.object(diagnostic.shutil, "which", return_value=None), \
                redirect_stderr(io.StringIO()) as output:
            self.assertEqual(diagnostic.main(), 2)
        self.assertIn("nslookup is required", output.getvalue())

    def test_execution_error_is_explicit(self):
        code, output, _ = self.run_main(lookup=OSError("permission denied"))
        self.assertEqual(code, 2)
        self.assertIn("permission denied", output)


if __name__ == "__main__":
    unittest.main()
