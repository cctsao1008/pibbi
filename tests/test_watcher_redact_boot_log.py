"""Synthetic tests for Watcher UART sanitization; never store real secrets."""
import runpy
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "watcher" / "redact-boot-log.py"
redact_line = runpy.run_path(str(SCRIPT))["redact_line"]


class WatcherRedactBootLogTests(unittest.TestCase):
    def test_sensitive_factory_labels(self):
        for field in ("SN", "EUI", "CODE", "DEVICE_KEY", "ACCESS_KEY",
                      "AI_KEY", "DEV_CTL_KEY", "BATCHID"):
            with self.subTest(field=field):
                result = redact_line("I (2304) : # %s: SYNTHETIC_PLACEHOLDER\n" % field)
                self.assertIn("REDACTED", result)
                self.assertNotIn("SYNTHETIC_PLACEHOLDER", result)
                self.assertIn("boot_ms=2304", result)

    def test_qr_and_token_fields(self):
        for field in ("qrcode content: DEMO",
                      "url=https://example.org, token=DEMO",
                      "SSID: DEMO", "password=DEMO",
                      "Authorization: Bearer EXAMPLE"):
            with self.subTest(field=field):
                self.assertEqual(redact_line(field + "\n"),
                                 "[REDACTED: device identifier or credential]\n")

    def test_mac_is_removed(self):
        self.assertEqual(redact_line("MAC: 00:11:22:33:44:55\n"),
                         "[REDACTED: device identifier or credential]\n")

    def test_boot_milestones_preserved(self):
        line = "I (1307) boot: Loaded app from partition at offset 0x110000\n"
        self.assertEqual(redact_line(line), line)

    def test_ready_timing_kept(self):
        line = "I (3028) spd2010: LCD panel create success, version: 1.0.1\n"
        self.assertEqual(redact_line(line), line)


if __name__ == "__main__":
    unittest.main()
