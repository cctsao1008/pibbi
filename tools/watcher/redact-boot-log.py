#!/usr/bin/env python3
"""Redact sensitive Watcher UART lines before sharing a boot log.

Source log remains local and private. Output is stdout only, not a new file.
Conservative: removes entire matching lines (including MAC, serials, codes,
device/cloud/API access keys, QR content, SSID, tokens and credentials).
No guarantee for unanticipated formats: always inspect output manually.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SENSITIVE = re.compile(
    r"(?ix)"
    r"(?:"
    r"\#\s*(?:SN|EUI|CODE|BATCHID|DEVICE_KEY|ACCESS_KEY|AI_KEY|DEV_CTL_KEY)\s*:"
    r"|\b(?:MAC|SSID|PASSWORD|PASSWD|PASSPHRASE|API_KEY|ACCESS_KEY|AI_KEY|"
    r"DEVICE_KEY|DEV_CTL_KEY|TOKEN|AUTHORIZATION|CREDENTIAL|QR\s*CODE)\b\s*[:=]"
    r"|\bqr(?:code|_code)\s+content\s*:"
    r"|\bBearer\s+[A-Za-z0-9_.-]+"
    r"|\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"
    r")"
)
TIMESTAMP = re.compile(r"\((\d{1,8})\)")


def redact_line(line: str) -> str:
    if not SENSITIVE.search(line):
        return line
    m = TIMESTAMP.search(line)
    prefix = "boot_ms=%s " % m.group(1) if m else ""
    ending = "\n" if line.endswith("\n") else ""
    return ("[%sREDACTED: device identifier or credential]\n" % prefix) if ending else (
        "[%sREDACTED: device identifier or credential]" % prefix
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Private local log to redact")
    args = parser.parse_args()
    try:
        with args.input.open("r", encoding="utf-8-sig", errors="replace") as src:
            for line in src:
                sys.stdout.write(redact_line(line))
    except OSError as exc:
        parser.exit(2, "Cannot read log: %s\n" % exc)
    print("[review output manually before external sharing]", file=sys.stderr)


if __name__ == "__main__":
    main()
