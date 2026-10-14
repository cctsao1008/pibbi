#!/usr/bin/env python3
"""Read-only HX6538 Native/SSCMA source and build-evidence preflight.

No make, firmware image generation, serial I/O, reset, or flashing.
Requires Python 3.8+ and Git. The only write is the audit JSON in artifacts/.
"""

import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


OBSERVED_SDK_SHA = "3ac4e9f557f09fbe4e62806c2a19b5e8a23a9a70"
SSCMA_SUBMODULE = "EPII_CM55M_APP_S/library/sscma_micro"
NATIVE_APP = "EPII_CM55M_APP_S/app/scenario_app/tflm_face_embedding"
SSCMA_APP = "EPII_CM55M_APP_S/app/scenario_app/sscma"


def git(cwd, *args):
    result = subprocess.run(
        ["git", "-C", str(cwd), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError("git " + " ".join(args) + ": " + result.stderr.strip())
    return result.stdout.strip()


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            data = stream.read(1024 * 1024)
            if not data:
                break
            digest.update(data)
    return digest.hexdigest()


def native_build_evidence(root, sdk_sha):
    manifest_path = (
        root / "artifacts" / "hx6538" / "build"
        / sdk_sha[:12] / "build-manifest.json"
    )
    if not manifest_path.is_file():
        return {"status": "NOT_FOUND", "manifest": str(manifest_path)}

    try:
        info = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        elf_info = info["Elf"]
        source = Path(elf_info["Artifact"])
        artifact = source if source.is_file() else manifest_path.parent / source.name
        evidence = {
            "manifest": str(manifest_path),
            "manifest_sdk_sha": info.get("SdkCommit"),
            "elf": str(artifact),
            "elf_bytes": elf_info.get("Bytes"),
            "expected_sha256": elf_info.get("Sha256"),
        }
        if info.get("SdkCommit") != sdk_sha:
            evidence["status"] = "SDK_SHA_MISMATCH"
        elif not artifact.is_file():
            evidence["status"] = "ELF_NOT_FOUND"
        else:
            digest = file_sha256(artifact)
            evidence["actual_sha256"] = digest
            evidence["status"] = (
                "VERIFIED"
                if digest.lower() == str(elf_info.get("Sha256", "")).lower()
                else "ELF_HASH_MISMATCH"
            )
        return evidence
    except (OSError, ValueError, KeyError, TypeError) as error:
        return {"status": "INVALID_MANIFEST", "error": str(error),
                "manifest": str(manifest_path)}


def audit(root):
    sdk = root / "third_party" / "sscma-example-we2"
    if not sdk.is_dir():
        raise RuntimeError("Missing SDK: {} (run bootstrap-hx6538.ps1)".format(sdk))

    sdk_sha = git(sdk, "rev-parse", "HEAD")
    dirty = git(sdk, "status", "--porcelain=v1", "--untracked-files=all").splitlines()
    gitlink = git(sdk, "ls-tree", "HEAD", "--", SSCMA_SUBMODULE)
    fields = gitlink.split()
    linked_sha = fields[2] if len(fields) >= 3 and fields[0] == "160000" else None
    submodule_dir = sdk / SSCMA_SUBMODULE
    try:
        checked_out_sha = git(submodule_dir, "rev-parse", "HEAD")
    except (RuntimeError, OSError):
        checked_out_sha = None

    native_required = [
        NATIVE_APP + "/tflm_face_embedding.c",
        NATIVE_APP + "/tflm_face_embedding.mk",
        NATIVE_APP + "/tflm_face_embedding.ld",
    ]
    sscma_required = [
        SSCMA_APP + "/sscma.cpp",
        SSCMA_APP + "/sscma.mk",
        SSCMA_APP + "/linker/watcher.ld",
        SSCMA_SUBMODULE + "/sscma/main_task.hpp",
        SSCMA_SUBMODULE + "/porting/himax/we2",
        SSCMA_SUBMODULE + "/sscma/callback",
    ]
    native_missing = [p for p in native_required if not (sdk / p).exists()]
    sscma_missing = [p for p in sscma_required if not (sdk / p).exists()]
    if linked_sha and checked_out_sha != linked_sha:
        sscma_missing.append(
            "SSCMA-Micro checkout does not match SDK gitlink "
            "(expected {}, got {})".format(linked_sha, checked_out_sha)
        )

    return {
        "schema_version": 1,
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "kind": "READ_ONLY_SOURCE_PREFLIGHT",
        "sdk_path": str(sdk),
        "sdk_sha": sdk_sha,
        "sdk_matches_observed_reference": sdk_sha == OBSERVED_SDK_SHA,
        "sdk_worktree_clean": not dirty,
        "sdk_worktree_dirty_entries": len(dirty),
        "sscma_submodule_expected_sha": linked_sha,
        "sscma_submodule_checked_out_sha": checked_out_sha,
        "native": {
            "app_type": "tflm_face_embedding",
            "source_status": "READY" if not native_missing else "BLOCKED",
            "missing": native_missing,
            "local_elf_evidence": native_build_evidence(root, sdk_sha),
        },
        "sscma": {
            "app_type": "sscma",
            "target": "SENSECAP_WATCHER",
            "source_status": "READY" if not sscma_missing else "BLOCKED",
            "missing": sscma_missing,
            "local_elf_evidence": {
                "status": "NOT_ASSESSED",
                "reason": "No SSCMA build has been completed by this read-only audit",
            },
        },
        "device_validation": "NOT_ATTEMPTED",
        "writes_vendor_sources": False,
        "builds_or_flashes_firmware": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root", type=Path, default=Path(__file__).resolve().parents[2],
        help="pibbi root (default: inferred from script location)",
    )
    parser.add_argument(
        "--output", type=Path,
        help="report JSON destination (default: artifacts/hx6538/analysis)",
    )
    args = parser.parse_args()
    root = args.repo_root.resolve()
    report = audit(root)

    output = args.output
    if output is None:
        output = root / "artifacts" / "hx6538" / "analysis" / "build-matrix-audit.json"
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                      encoding="utf-8")

    print("SDK       :", report["sdk_sha"])
    print("Submodule :", report["sscma_submodule_expected_sha"])
    print("Native    :", report["native"]["source_status"],
          "| ELF:", report["native"]["local_elf_evidence"]["status"])
    print("SSCMA     :", report["sscma"]["source_status"])
    for entry in report["sscma"]["missing"]:
        print("  missing :", entry)
    print("Report    :", output)
    print("Safety    : NO BUILD / NO FLASH / NO DEVICE I/O")


if __name__ == "__main__":
    main()
