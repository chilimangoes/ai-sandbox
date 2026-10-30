"""Check native pairing output in both QR-before-URL and URL-before-QR order."""

import importlib.util
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlencode, urlsplit


path = Path(__file__).resolve().parents[2] / "docker/t3-output.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("t3_output", path)
output = importlib.util.module_from_spec(spec)
spec.loader.exec_module(output)
PUBLIC_URL = "http://127.91.42.17:3773"
NATIVE_URL = "http://172.17.0.2:3773/pair#token=test-token"
PAIRING_URL = PUBLIC_URL + "/pair#token=test-token"
NATIVE_QR = "  ▄█▀  \n  █▀▄  \n"


class OutputTests(unittest.TestCase):
    def rewrite(self, text):
        result = io.StringIO()
        with patch.object(output, "render_qr", return_value="HOST QR\n") as render:
            output.rewrite(io.StringIO(text), PUBLIC_URL, result)
        return result.getvalue(), render

    def test_pair_updates_qr_url_and_app_link_together(self):
        app_link = "t3code://pair?" + urlencode({"url": NATIVE_URL})
        result, render = self.rewrite(
            "Pairing with server.\n\n" + NATIVE_QR
            + f"\nPairing URL: {NATIVE_URL}\nApp link: {app_link}\nToken: test-token\n"
        )
        render.assert_called_once_with(PAIRING_URL)
        self.assertNotIn(NATIVE_QR, result)
        self.assertIn("HOST QR", result)
        self.assertIn(f"Pairing URL: {PAIRING_URL}", result)
        link = next(line.removeprefix("App link: ") for line in result.splitlines() if line.startswith("App link: "))
        self.assertEqual(parse_qs(urlsplit(link).query)["url"], [PAIRING_URL])
        self.assertIn("Token: test-token", result)

    def test_serve_updates_qr_after_url(self):
        result, render = self.rewrite(
            f"Connection string: http://172.17.0.2:3773\nPairing URL: {NATIVE_URL}\n\n"
            + NATIVE_QR + "\nserver log\n"
        )
        render.assert_called_once_with(PAIRING_URL)
        self.assertIn(f"Connection string: {PUBLIC_URL}", result)
        self.assertIn("server log\n", result)
        self.assertNotIn(NATIVE_QR, result)

    def test_structured_pairing_field(self):
        result, _ = self.rewrite(f"  pairingUrl: {NATIVE_URL}\n")
        self.assertEqual(result, f"  pairingUrl: {PAIRING_URL}\n")

    def test_ordinary_output_is_exact(self):
        text = 'diagnostic\n{"sessions": []}\nno trailing newline'
        result, render = self.rewrite(text)
        self.assertEqual(result, text)
        render.assert_not_called()

    def test_unrecognized_qr_is_preserved(self):
        result, render = self.rewrite(NATIVE_QR + "unrelated output\n")
        self.assertEqual(result, NATIVE_QR + "unrelated output\n")
        render.assert_not_called()

    def test_custom_port_and_https_pairing_addresses_are_preserved(self):
        for url in ["http://172.17.0.2:4999/pair#token=test-token",
                    "https://example.ts.net/pair#token=test-token"]:
            result, _ = self.rewrite(f"Pairing URL: {url}\n")
            self.assertEqual(result, f"Pairing URL: {url}\n")


if __name__ == "__main__":
    unittest.main()
