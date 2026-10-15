#!/usr/bin/env python3
"""B2d private, OFFLINE-only ESP32-S3 backup and OTA candidate inspection.

Read-only local files. NEVER connects to a device, extracts secrets, exports
images, or writes metadata. Do not share/upload backup data or NVS contents.
"""
from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import struct
from pathlib import Path

FLASH_SIZE = 0x2000000
PARTITION_OFFSET = 0x8000
PARTITION_LENGTH = 0x1000
EXPECTED_PARTITION_SHA256 = (
    "535EA803C19353B47BACEA78DE4642692920CD925402233666FF9E7EB9189D73"
)
NVS_OFFSET, NVS_SIZE = 0x9000, 0x32000
OTADATA_OFFSET, OTADATA_SIZE = 0x10D000, 0x2000
SLOTS = (
    ("ota_0", 0x110000, 0xC00000),
    ("ota_1", 0xD10000, 0xC00000),
)
STATES = {
    0: "NEW",
    1: "PENDING_VERIFY",
    2: "VALID",
    3: "INVALID",
    4: "ABORTED",
    0xFFFFFFFF: "UNDEFINED",
}


def read_region(stream, offset: int, length: int) -> bytes:
    stream.seek(offset)
    data = stream.read(length)
    if len(data) != length:
        raise ValueError("Truncated backup at offset 0x%x" % offset)
    return data


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest().upper()


def ota_entry(partition: bytes, sector: int) -> dict:
    """IDA esp_ota_select_entry_t at offset sector*4096; CRC per IDF v5.2.1."""
    if sector not in (0, 1) or len(partition) != OTADATA_SIZE:
        raise ValueError("OTA partition length or sector invalid")
    offset = sector * 0x1000
    seq, _, state, saved_crc = struct.unpack_from("<I20sII", partition, offset)
    # Espressif v5.2.1 otatool.py: binascii.crc32(pack('I', seq), 0xffffffff)
    calculated_crc = binascii.crc32(struct.pack("<I", seq), 0xFFFFFFFF) & 0xFFFFFFFF
    crc_ok = saved_crc == calculated_crc
    selectable = seq != 0xFFFFFFFF and state not in (3, 4) and crc_ok
    # This is the bootloader validity predicate; seq==0 is anomalous
    # for the slot-mapping formula, so exclude it from confident decisions.
    return {
        "sector": sector,
        "ota_seq": "erased" if seq == 0xFFFFFFFF else seq,
        "state": STATES.get(state, "UNKNOWN(0x%08X)" % state),
        "crc_ok": crc_ok if seq != 0xFFFFFFFF else None,
        "bootloader_selectable": selectable,
        "_seq": seq,
    }


def candidate_ota(entries: list[dict]) -> tuple[str, str]:
    valid = [e for e in entries if e["bootloader_selectable"]]
    if not valid:
        # The verified partition table has no factory app partition.
        # IDF bootloader tries ota_0 when no valid otadata is available.
        return "ota_0", "FALLBACK_IF_NO_VALID_OTADATA"
    winner = max(valid, key=lambda e: (e["_seq"], -e["sector"]))
    if winner["_seq"] == 0:
        return "UNKNOWN", "OTA_SEQUENCE_ZERO_UNEXPECTED"
    slot = (winner["_seq"] - 1) % len(SLOTS)
    return SLOTS[slot][0], "OTA_METADATA_CANDIDATE_ONLY"


def header_probe(stream, offset: int) -> dict:
    """Lightweight header check only; not full ESP image validation."""
    header = read_region(stream, offset, 24)
    magic = header[0]
    segments = header[1]
    return {
        "header_magic_e9": magic == 0xE9,
        "segment_count": segments if magic == 0xE9 else None,
        "plausible_header": magic == 0xE9 and 1 <= segments <= 16,
        "note": "HEADER_ONLY_NOT_IMAGE_SIGNATURE_OR_CHECKSUM_VALIDATION",
    }


def inspect(backup_dir: Path) -> dict:
    whole = backup_dir / "esp32s3-full-32MiB-PRIVATE.bin"
    manifest = backup_dir / "manifest-PRIVATE.json"
    if not whole.is_file() or not manifest.is_file():
        raise ValueError("Expected full ESP32-S3 backup and private manifest in directory")
    data = json.loads(manifest.read_text(encoding="utf-8-sig"))
    if data.get("status") != "READ_ONLY_BACKUP_PASS" or data.get("independent_region_match") != "PASS":
        raise ValueError("Backup manifest does not record required PASS gates")
    if whole.stat().st_size != FLASH_SIZE:
        raise ValueError("Backup length is not 32 MiB")

    digest = sha256_file(whole)
    if digest != str(data.get("full_flash_sha256", "")).upper():
        raise ValueError("Full backup SHA256 does not match local manifest")

    with whole.open("rb") as stream:
        partition = read_region(stream, PARTITION_OFFSET, PARTITION_LENGTH)
        actual_partition_sha = hashlib.sha256(partition).hexdigest().upper()
        if actual_partition_sha != EXPECTED_PARTITION_SHA256:
            raise ValueError("Partition SHA mismatch: not the verified physical layout")
        if data.get("partition_sha256", "").upper() != actual_partition_sha:
            raise ValueError("Partition SHA mismatch versus local manifest")

        for path, offset, size, manifest_field in (
            ("partition-table.bin", PARTITION_OFFSET, PARTITION_LENGTH, "partition_sha256"),
            ("nvsfactory-PRIVATE.bin", NVS_OFFSET, NVS_SIZE, "nvsfactory_sha256"),
            ("otadata-PRIVATE.bin", OTADATA_OFFSET, OTADATA_SIZE, "otadata_sha256"),
        ):
            region = read_region(stream, offset, size)
            local_file = backup_dir / path
            if not local_file.is_file() or local_file.stat().st_size != size:
                raise ValueError("Missing or truncated local cross-check file")
            if local_file.read_bytes() != region:
                raise ValueError("Independent partition read differs from full flash image")
            expected = str(data.get(manifest_field, "")).upper()
            if hashlib.sha256(region).hexdigest().upper() != expected:
                raise ValueError("Independent region SHA mismatch vs private manifest")

        otadata = read_region(stream, OTADATA_OFFSET, OTADATA_SIZE)
        entries = [ota_entry(otadata, i) for i in (0, 1)]
        selection, reason = candidate_ota(entries)
        images = {
            name: {"offset": "0x%X" % offset, **header_probe(stream, offset)}
            for name, offset, size in SLOTS
        }

    safe_entries = [{k: v for k, v in entry.items() if not k.startswith("_")}
                    for entry in entries]
    return {
        "status": "OFFLINE_BACKUP_INTEGRITY_PASS",
        "bytes_full_flash": FLASH_SIZE,
        "full_flash_sha256": digest,
        "partition_table_sha256": actual_partition_sha,
        "independent_partition_files": "MATCH",
        "ota_select_records": safe_entries,
        "inferred_boot_candidate": selection,
        "candidate_basis": reason,
        "app_image_headers": images,
        "limitations": (
            "OTA metadata predicts a candidate, not the confirmed running app. "
            "Bootloader rollback, anti-rollback settings, image validation or "
            "app crashes may select another slot. A magic header does not prove "
            "the whole image is valid. Restore has NOT been tested."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup-dir", required=True, type=Path,
                        help="Private B2c backup folder, never upload it")
    args = parser.parse_args()
    try:
        report = inspect(args.backup_dir)
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        parser.exit(2, "OFFLINE_BACKUP_INSPECTION_FAIL: %s\n" % exc)
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
