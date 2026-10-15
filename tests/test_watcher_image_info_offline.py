"""B2e parser tests; no private firmware image and no physical hardware."""
import runpy
import unittest
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "tools" / "watcher" / "verify-ota0-image-offline.py"
parse_image_info = runpy.run_path(str(PATH))["parse_image_info"]

SAMPLE = """ESP32-S3 image header
Segments: 6
Chip ID: 9 (ESP32-S3)
ESP32-S3 image footer
Checksum: 0x27 (valid)
Validation hash: """ + "a" * 64 + " (valid)\n"


class WatcherImageVerifierTests(unittest.TestCase):
    def test_valid_checksum_and_appended_hash(self):
        r = parse_image_info(SAMPLE, 0)
        self.assertEqual(r["status"], "IMAGE_CHECK_PASS")
        self.assertTrue(r["chip_id_verified"])
        self.assertTrue(r["checksum_valid"])
        self.assertEqual(r["appended_sha256"], "VALID")
        self.assertEqual(r["segments"], 6)

    def test_invalid_checksum_rejected(self):
        r = parse_image_info(SAMPLE.replace("(valid)", "(invalid)", 1), 0)
        self.assertEqual(r["status"], "IMAGE_CHECK_INCOMPLETE_OR_FAIL")
        self.assertFalse(r["checksum_valid"])

    def test_invalid_hash_rejected(self):
        r = parse_image_info(SAMPLE.replace("a"*64 + " (valid)", "a"*64 + " (invalid)"), 0)
        self.assertEqual(r["status"], "IMAGE_CHECK_INCOMPLETE_OR_FAIL")
        self.assertEqual(r["appended_sha256"], "INVALID")

    def test_nonzero_esptool_exit_rejected(self):
        self.assertEqual(parse_image_info(SAMPLE, 2)["status"],
                         "IMAGE_CHECK_INCOMPLETE_OR_FAIL")

    def test_wrong_chip_or_missing_header_rejected(self):
        wrong_chip = SAMPLE.replace("9 (ESP32-S3)", "5 (ESP32-C3)")
        self.assertEqual(parse_image_info(wrong_chip, 0)["status"],
                         "IMAGE_CHECK_INCOMPLETE_OR_FAIL")
        self.assertEqual(parse_image_info("", 0)["status"],
                         "IMAGE_CHECK_INCOMPLETE_OR_FAIL")

    def test_optional_hash_absent_is_explicit(self):
        r = parse_image_info(SAMPLE.replace("Validation hash: " + "a"*64 + " (valid)",
                                            "Validation hash: Not appended"), 0)
        self.assertEqual(r["status"], "IMAGE_CHECK_PASS")
        self.assertEqual(r["appended_sha256"], "NOT_APPENDED")


if __name__ == "__main__":
    unittest.main()
