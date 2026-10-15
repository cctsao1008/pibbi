"""Tests for offline-only OTA1 occupancy checks; synthetic bytes only."""
import io
import runpy
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "watcher" / "inspect-ota1-occupancy-offline.py"
scan_region = runpy.run_path(str(SCRIPT))["scan_region"]


class TestOta1Occupancy(unittest.TestCase):
    def test_all_ff_region(self):
        stream = io.BytesIO(b"\x00" * 10 + b"\xff" * 34 + b"\x00")
        r = scan_region(stream, 10, 34, chunk_size=7)
        self.assertEqual(r["offset"], "0xA")
        self.assertEqual(r["length"], 34)
        self.assertTrue(r["fully_erased_all_ff"])
        self.assertEqual(r["non_ff_byte_count"], 0)
        self.assertIsNone(r["first_non_ff_offset"])

    def test_detects_sparse_non_ff_bytes_at_chunk_edges(self):
        stream = io.BytesIO(b"\xff" * 7 + b"\x00" + b"\xff" * 12 + b"\x01" + b"\xff" * 2)
        r = scan_region(stream, 0, 23, chunk_size=5)
        self.assertFalse(r["fully_erased_all_ff"])
        self.assertEqual(r["non_ff_byte_count"], 2)
        self.assertEqual(r["first_non_ff_offset"], "0x7")
        self.assertEqual(r["last_non_ff_offset"], "0x14")

    def test_outside_region_not_counted(self):
        stream = io.BytesIO(b"\x00" + b"\xff" * 4 + b"\x01")
        r = scan_region(stream, 1, 4, chunk_size=16)
        self.assertTrue(r["fully_erased_all_ff"])

    def test_truncated_region_rejected(self):
        with self.assertRaises(ValueError):
            scan_region(io.BytesIO(b"\xff" * 5), 0, 6)

    def test_invalid_dimensions_rejected(self):
        with self.assertRaises(ValueError):
            scan_region(io.BytesIO(b"\xff" * 3), -1, 2)
        with self.assertRaises(ValueError):
            scan_region(io.BytesIO(b"\xff" * 3), 0, 0)
        with self.assertRaises(ValueError):
            scan_region(io.BytesIO(b"\xff" * 3), 0, 2, chunk_size=0)


if __name__ == "__main__":
    unittest.main()
