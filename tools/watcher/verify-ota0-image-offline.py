#!/usr/bin/env python3
"""B2e: verify original ESP32-S3 ota_0 app integrity using esptool image_info.

Reads the verified PRIVATE B2c backup only; no COM/flash actions. Makes one
temporary app-slot slice in the same private backup folder and deletes it.
Prints only integrity status, not app contents, version, identity or credentials.
"""
from __future__ import annotations

import argparse
import json
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

OTA0_OFFSET = 0x110000
OTA0_SIZE = 0xC00000
EXPECTED_CHIP_ID = 9  # ESP32-S3


def parse_image_info(output: str, status: int) -> dict:
    checksum = re.search(r"^Checksum:\s+0x[0-9a-f]+\s+\((valid|invalid[^)]*)\)",
                         output, re.I | re.M)
    digest = re.search(r"^Validation hash:\s+(Not appended|[0-9a-f]{64}\s+\((valid|invalid)\))",
                       output, re.I | re.M)
    chip = re.search(r"^Chip ID:\s+(\d+)\s+\(([^)]*)\)", output, re.I | re.M)
    segments = re.search(r"^Segments:\s+(\d+)", output, re.I | re.M)
    checksum_ok = bool(checksum and checksum.group(1).lower() == "valid")
    digest_state = "NOT_REPORTED"
    if digest:
        digest_state = ("NOT_APPENDED" if digest.group(1).lower() == "not appended"
                        else digest.group(2).upper() if digest.group(2) else "UNKNOWN")
    chip_ok = bool(chip and int(chip.group(1)) == EXPECTED_CHIP_ID
                   and "ESP32-S3" in chip.group(2).upper())
    segment_count = int(segments.group(1)) if segments else None
    outcome = (
        "IMAGE_CHECK_PASS" if status == 0 and checksum_ok and chip_ok
        and segment_count is not None and 1 <= segment_count <= 16
        and digest_state in ("VALID", "NOT_APPENDED") else "IMAGE_CHECK_INCOMPLETE_OR_FAIL"
    )
    return {
        "status": outcome,
        "source": "private_ota_0_image_info",
        "esptool_exit_code": status,
        "chip_id_expected": EXPECTED_CHIP_ID,
        "chip_id_verified": chip_ok,
        "segments": segment_count,
        "checksum_valid": checksum_ok,
        "appended_sha256": digest_state,
        "note": (
            "Checksum and optional appended digest verify ESP image bytes only. "
            "NOT proof of actual running slot, absence of crashes, or restore test. "
            "No on-device write performed."
        ),
    }


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--backup-dir", type=Path, required=True)
    args = p.parse_args()
    backup = args.backup_dir.resolve(strict=True)
    if not backup.is_dir():
        p.error("not a backup directory")

    # Re-use the existing offline verifier before slicing a potentially
    # sensitive firmware image. Includes full SHA256 and NVS/OTA comparison.
    sibling = Path(__file__).resolve().parent / "inspect-backup-offline.py"
    inspect = runpy.run_path(str(sibling))["inspect"]
    try:
        verified = inspect(backup)
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        p.exit(2, "OFFLINE_BACKUP_GATE_FAIL: %s\n" % exc)
    if verified["status"] != "OFFLINE_BACKUP_INTEGRITY_PASS":
        p.exit(2, "OFFLINE_BACKUP_GATE_FAIL: unexpected inspection status\n")
    if verified["inferred_boot_candidate"] != "ota_0":
        p.exit(2, "OFFLINE_BACKUP_GATE_FAIL: candidate is not ota_0; review before proceeding\n")
    if not verified["app_image_headers"]["ota_0"]["plausible_header"]:
        p.exit(2, "OFFLINE_BACKUP_GATE_FAIL: ota_0 image header is not plausible\n")

    whole = backup / "esp32s3-full-32MiB-PRIVATE.bin"
    with tempfile.TemporaryDirectory(prefix=".pibbi-private-image-info-", dir=backup) as temp:
        image = Path(temp) / "factory-ota0-PRIVATE.bin"
        with whole.open("rb") as stream, image.open("wb") as dest:
            stream.seek(OTA0_OFFSET)
            remaining = OTA0_SIZE
            while remaining:
                chunk = stream.read(min(1024 * 1024, remaining))
                if not chunk:
                    p.exit(2, "OFFLINE_BACKUP_GATE_FAIL: image unexpectedly truncated\n")
                dest.write(chunk)
                remaining -= len(chunk)
        # This command only reads the temporary file. No --port argument.
        proc = subprocess.run(
            [sys.executable, "-m", "esptool", "--chip", "esp32s3",
             "image_info", "--version", "2", str(image)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            check=False,
        )
        report = parse_image_info(proc.stdout, proc.returncode)
    # Temporary extracted app file is removed on normal exit.
    print(json.dumps(report, indent=2))
    if report["status"] != "IMAGE_CHECK_PASS":
        p.exit(2, "OFFLINE_OTA0_IMAGE_VALIDATION_NOT_PROVEN; do NOT flash.\n")


if __name__ == "__main__":
    main()
