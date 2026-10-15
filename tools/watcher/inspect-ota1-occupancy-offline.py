#!/usr/bin/env python3
"""B2f private, offline-only OTA1 occupancy inspection.

A missing ESP header is not proof the partition is erased. Before proposing
any OTA1 write, check every byte of the 12 MiB destination. This tool never
modifies any files, connects to a device or emits flash contents.
"""
from __future__ import annotations

import argparse
import json
import runpy
from pathlib import Path

OTA1_OFFSET = 0xD10000
OTA1_SIZE = 0xC00000
CHUNK_SIZE = 1024 * 1024


def scan_region(stream, start: int, length: int, chunk_size: int = CHUNK_SIZE) -> dict:
    if start < 0 or length <= 0 or chunk_size <= 0:
        raise ValueError("Invalid region extent")
    stream.seek(start)
    remaining = length
    non_ff_count = 0
    first = None
    last = None
    consumed = 0
    while remaining:
        data = stream.read(min(chunk_size, remaining))
        if not data:
            raise ValueError("Region is truncated")
        for j, value in enumerate(data):
            if value != 0xFF:
                non_ff_count += 1
                last = start + consumed + j
                if first is None:
                    first = last
        remaining -= len(data)
        consumed += len(data)
    return {
        "offset": "0x%X" % start,
        "length": length,
        "fully_erased_all_ff": non_ff_count == 0,
        "non_ff_byte_count": non_ff_count,
        "first_non_ff_offset": "0x%X" % first if first is not None else None,
        "last_non_ff_offset": "0x%X" % last if last is not None else None,
    }


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--backup-dir", required=True, type=Path)
    args = p.parse_args()
    try:
        folder = args.backup_dir.resolve(strict=True)
        # Revalidate original backup integrity, including NVS/OTA independent copies.
        inspect = runpy.run_path(str(Path(__file__).with_name("inspect-backup-offline.py")))["inspect"]
        result = inspect(folder)
        if result["status"] != "OFFLINE_BACKUP_INTEGRITY_PASS":
            raise ValueError("B2d integrity gate did not pass")
        with (folder / "esp32s3-full-32MiB-PRIVATE.bin").open("rb") as f:
            scan = scan_region(f, OTA1_OFFSET, OTA1_SIZE)
        scan.update({
            "status": "OFFLINE_OTA1_OCCUPANCY_PASS",
            "source": "private_full_flash_backup",
            "interpretation": (
                "ALL_FF_IN_CAPTURED_SNAPSHOT" if scan["fully_erased_all_ff"]
                else "NON_FF_DATA_PRESENT_DO_NOT_OVERWRITE_WITHOUT_REVIEW"
            ),
            "limits": (
                "A fully erased snapshot does not guarantee the device has not "
                "changed since backup, or grant flashing permission. A non-E9 "
                "header alone never proves a region is unused."
            ),
        })
    except (OSError, ValueError, KeyError, TypeError) as exc:
        p.exit(2, "OFFLINE_OTA1_INSPECTION_FAIL: %s\n" % exc)
    print(json.dumps(scan, indent=2))


if __name__ == "__main__":
    main()
