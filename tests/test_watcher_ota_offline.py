"""Host-only regression tests for private offline Watcher OTA inspector."""
import binascii
import io
import runpy
import struct
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "watcher" / "inspect-backup-offline.py"
impl = runpy.run_path(str(SCRIPT))
ota_entry = impl["ota_entry"]
candidate_ota = impl["candidate_ota"]
header_probe = impl["header_probe"]

STATE_VALID = 2


def make_ota_record(seq=0xFFFFFFFF, state=0xFFFFFFFF, corrupt_crc=False):
    raw = bytearray(b"\xff" * 0x2000)
    crc = binascii.crc32(struct.pack("<I", seq), 0xFFFFFFFF) & 0xFFFFFFFF
    if corrupt_crc:
        crc ^= 0x1
    struct.pack_into("<I20sII", raw, 0, seq, b"\0" * 20, state, crc)
    return raw


class WatcherOtaOfflineTests(unittest.TestCase):
    def test_crc_matches_esp_idf_otatool_semantics(self):
        raw = make_ota_record(seq=1, state=STATE_VALID)
        entry = ota_entry(raw, 0)
        self.assertTrue(entry["crc_ok"])
        self.assertTrue(entry["bootloader_selectable"])
        self.assertEqual(candidate_ota([entry])[:1], ("ota_0",))

    def test_second_slot_from_sequence_two(self):
        raw = make_ota_record(seq=2, state=STATE_VALID)
        entry = ota_entry(raw, 0)
        self.assertEqual(candidate_ota([entry])[0], "ota_1")

    def test_invalid_crc_not_selectable(self):
        raw = make_ota_record(seq=2, state=STATE_VALID, corrupt_crc=True)
        self.assertFalse(ota_entry(raw, 0)["bootloader_selectable"])

    def test_marked_aborted_is_not_selectable(self):
        raw = make_ota_record(seq=3, state=4)
        self.assertFalse(ota_entry(raw, 0)["bootloader_selectable"])

    def test_fallback_does_not_claim_active_running_slot(self):
        raw = make_ota_record()
        entry = ota_entry(raw, 0)
        candidate, reason = candidate_ota([entry])
        self.assertEqual(candidate, "ota_0")
        self.assertEqual(reason, "FALLBACK_IF_NO_VALID_OTADATA")

    def test_higher_valid_sequence_wins(self):
        raw1 = make_ota_record(seq=2, state=STATE_VALID)
        raw2 = make_ota_record(seq=5, state=STATE_VALID)
        e0 = ota_entry(raw1, 0)
        e1 = ota_entry(raw2, 0)
        self.assertEqual(candidate_ota([e0, e1])[0], "ota_0")

    def test_header_magic_is_only_plausibility(self):
        self.assertTrue(header_probe(io.BytesIO(bytes([0xE9, 1]) + b"\x00"*22), 0)["plausible_header"])
        self.assertFalse(header_probe(io.BytesIO(bytes([0xFF]*24)), 0)["plausible_header"])

    def test_rejects_bad_sector_and_size(self):
        with self.assertRaises(ValueError):
            ota_entry(b"\xff"*32, 0)
        with self.assertRaises(ValueError):
            ota_entry(bytes(8192), 3)


if __name__ == "__main__":
    unittest.main()
