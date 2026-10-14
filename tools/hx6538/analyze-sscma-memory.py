#!/usr/bin/env python3
"""Offline, read-only HX6538 SSCMA ELF/MAP memory analysis.

Never builds, generates an image, flashes a device, or changes ELF/MAP inputs.
Requires the pinned Arm GNU binutils in PATH. Python 3.8+.
"""
import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

SDK_SHA = "37fed7a8e27b9d50f64b6784c3aff7bbf04cf70d"
REGIONS = {
    "CM55M_S_APP_ROM": (0x10000000, 0x10040000),
    "CM55M_S_APP_DATA": (0x30000000, 0x30040000),
    "CM55M_S_SRAM": (0x34000000, 0x34054000),
    "CM55M_S_EL_ALLOC": (0x34054000, 0x3416A000),
}
IMPORTANT = (".text", ".text.ext", ".rodata", ".data", ".bss",
             ".ucHeap", ".elHeap", ".heap", ".stack", ".noinit")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as fp:
        for chunk in iter(lambda: fp.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run(command):
    done = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, errors="replace", check=False)
    if done.returncode:
        raise RuntimeError("Tool failed: {}\n{}".format(" ".join(map(str, command)), done.stderr[-3000:]))
    return done.stdout


def region_for(address, size=1):
    for name, (start, end) in REGIONS.items():
        if start <= address and address + size <= end:
            return name
    return None


def parse_sections(text):
    """Parse GNU objdump -h, preserving VMA, LMA, and allocation flags."""
    output = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        fields = line.split()
        if len(fields) < 7 or not fields[0].isdigit() or not fields[6].startswith("2**"):
            continue
        try:
            name, size, vma, lma = fields[1], int(fields[2], 16), int(fields[3], 16), int(fields[4], 16)
        except ValueError:
            continue
        flags = [x.strip() for x in lines[i + 1].split(",")] if i + 1 < len(lines) else []
        flags = [f for f in flags if f]
        output.append({"name": name, "size_bytes": size, "vma": "0x{:08x}".format(vma),
                       "lma": "0x{:08x}".format(lma), "region": region_for(vma, size),
                       "flags": flags, "allocated": "ALLOC" in flags,
                       "has_file_contents": "CONTENTS" in flags})
    if not output:
        raise ValueError("No objdump section headers parsed; check binutils output")
    return output


def parse_symbols(text):
    symbols = []
    for line in text.splitlines():
        m = re.match(r"^\s*(\d+)\s+(\d+)\s+([a-zA-Z])\s+(.+)$", line)
        if not m:
            continue
        addr, size = int(m.group(1)), int(m.group(2))
        name = m.group(4).strip()
        symbols.append({"address": "0x{:08x}".format(addr), "size_bytes": size,
                        "type": m.group(3), "name": name, "region": region_for(addr, max(1, size))})
    return sorted(symbols, key=lambda x: x["size_bytes"], reverse=True)


def parse_map_sections(text):
    """Read GNU ld output headers (either same-line or wrapped placement)."""
    out = []
    lines = text.splitlines()
    header = re.compile(r"^(\.[\w.]+)\s+(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)(?:\s+load address\s+(0x[0-9a-fA-F]+))?")
    wrapped = re.compile(r"^\s+(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)(?:\s+load address\s+(0x[0-9a-fA-F]+))?")
    for i, line in enumerate(lines):
        m = header.match(line)
        if m:
            name, address, length, load = m.group(1, 2, 3, 4)
        elif re.fullmatch(r"\.[\w.]+\s*", line) and i + 1 < len(lines):
            next_line = wrapped.match(lines[i + 1])
            if not next_line:
                continue
            name, (address, length, load) = line.strip(), next_line.group(1, 2, 3)
        else:
            continue
        addr, size = int(address, 16), int(length, 16)
        out.append({"name": name, "vma": "0x{:08x}".format(addr),
                    "size_bytes": size, "region": region_for(addr, size),
                    "map_load_address": load})
    return out


def parse_linker_symbols(map_text, nm_text):
    names = ("__HeapBase", "__HeapLimit", "__StackLimit", "__StackTop")
    values = {}
    for name in names:
        matches = re.findall(r"^\s*(0x[0-9a-fA-F]+)\s+(?:PROVIDE\s*\(\s*)?" + re.escape(name) + r"\s*=", map_text, re.M)
        if not matches:
            matches = re.findall(r"^\s*([0-9a-fA-F]{8,})\s+[A-Za-z]\s+" + re.escape(name) + r"\s*$", nm_text, re.M)
            if matches:
                values[name] = int(matches[-1], 16)
                continue
        if matches:
            values[name] = int(matches[-1], 16)
    gap = values.get("__StackLimit", 0) - values.get("__HeapLimit", 0) if (
        "__StackLimit" in values and "__HeapLimit" in values) else None
    return {"addresses": {k: "0x{:08x}".format(v) for k, v in values.items()},
            "heap_to_stack_gap_bytes": gap}


def make_report(run_dir, prefix):
    elf = run_dir / "sscma-watcher.elf"
    map_file = run_dir / "sscma-watcher.elf.map"
    manifest_file = run_dir / "build-manifest.json"
    for path in (elf, map_file, manifest_file):
        if not path.is_file():
            raise FileNotFoundError("Missing required artifact: {}".format(path))
    manifest = json.loads(manifest_file.read_text(encoding="utf-8-sig"))
    if manifest.get("SdkCommit") != SDK_SHA or manifest.get("Status") != "BUILD_PASS_NOT_FLASHED":
        raise RuntimeError("Unreviewed SDK SHA or manifest status; refusing to analyze")
    checks = ((elf, manifest.get("Elf", {}).get("Sha256")),
              (map_file, manifest.get("Map", {}).get("Sha256")))
    for path, expected in checks:
        if not expected or digest(path) != expected.lower():
            raise RuntimeError("Missing or invalid SHA-256 in manifest: {}".format(path))
    obj_text = run([prefix + "objdump", "-h", str(elf)])
    nm_text = run([prefix + "nm", "-S", "--size-sort", "--radix=d", "--demangle", str(elf)])
    ph_text = run([prefix + "readelf", "-W", "-l", str(elf)])
    map_text = map_file.read_text(encoding="utf-8", errors="replace")
    sections = parse_sections(obj_text)
    map_sections = parse_map_sections(map_text)
    symbols = parse_symbols(nm_text)
    region_info = {}
    for name, (start, end) in REGIONS.items():
        allocated = [s for s in sections if s["allocated"] and s["region"] == name]
        region_info[name] = {
            "origin": "0x{:08x}".format(start), "end_exclusive": "0x{:08x}".format(end),
            "capacity_bytes": end - start, "section_allocated_bytes_sum": sum(s["size_bytes"] for s in allocated),
            "section_names": [s["name"] for s in allocated],
            "note": "Section sum; not free runtime heap or linker --print-memory-usage",
        }
    heap_symbols = [s for s in symbols if re.search(r"ucHeap|elHeap|tensor.?arena", s["name"], re.I)]
    linker = parse_linker_symbols(map_text, nm_text)
    warnings = [
        "Neither linker region occupancy nor ELF BSS size measures runtime heap use or stack high-water.",
        "APP_DATA contains executable .text.ext; do not equate ELF text bytes with APP_ROM usage.",
        "SDK revisions differ for Native vs SSCMA; no cross-framework overhead conclusion is valid.",
        "COPY linker sections (.heap/.stack) may have GNU objdump CONTENTS but lack ALLOC/PT_LOAD; check ELF program headers before calling them loadable bytes.",
        "VMA/LMA in ELF are not a complete signed flash image or boot-copy validation.",
    ]
    report = {
        "schema_version": 1, "kind": "READ_ONLY_VERIFIED_ELF_MAP_AUDIT",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "sdk_sha": SDK_SHA, "source_run": str(run_dir),
        "elf_sha256": digest(elf), "map_sha256": digest(map_file),
        "regions": region_info, "sections": sections, "map_sections": map_sections,
        "largest_symbols": symbols[:50], "heap_symbols": heap_symbols,
        "linker_heap_stack": linker, "warnings": warnings,
        "runtime_heap_status": "NOT_MEASURED", "hardware_execution": "NOT_ATTEMPTED",
    }
    return report, {"objdump-sections.txt": obj_text, "nm-symbols.txt": nm_text,
                    "readelf-program-headers.txt": ph_text}


def markdown(report):
    lines = ["# SSCMA Watcher ELF/MAP memory audit", "",
             "Static evidence only; verified against original build manifest SHA-256.", "",
             "## Region section accounting", "",
             "| Region | Capacity (B) | ALLOC sections sum (B) |", "|---|---:|---:|"]
    for name, x in report["regions"].items():
        lines.append("| {} | {} | {} |".format(name, x["capacity_bytes"], x["section_allocated_bytes_sum"]))
    lines.extend(["", "## Important sections (VMA and LMA)", "",
                  "| Section | VMA | LMA | Size (B) | Region | objdump CONTENTS | objdump ALLOC |",
                  "|---|---|---|---:|---|---|---|"])
    for s in report["sections"]:
        if s["name"] in IMPORTANT:
            lines.append("| {name} | {vma} | {lma} | {size_bytes} | {region} | {has_file_contents} | {allocated} |".format(**s))
    lines.extend(["", "## Linker MAP output sections (including COPY reservations)", "",
                  "| MAP section | VMA | Size (B) | Region |", "|---|---|---:|---|"])
    for s in report["map_sections"]:
        if s["name"] in IMPORTANT:
            lines.append("| {name} | {vma} | {size_bytes} | {region} |".format(**s))
    lines.extend(["", "## Heap and Tensor Arena candidate backing symbols", "",
                  "| Symbol | Address | Size (B) | Region |", "|---|---|---:|---|"])
    for s in report["heap_symbols"]:
        lines.append("| `{}` | {} | {} | {} |".format(s["name"].replace("|", "\\|"), s["address"], s["size_bytes"], s["region"]))
    if not report["heap_symbols"]:
        lines.append("| NOT FOUND | — | — | — |")
    limits = report["linker_heap_stack"]
    lines.extend(["", "## Linker heap/stack bounds", ""])
    for k, v in limits["addresses"].items():
        lines.append("- `{}`: {}".format(k, v))
    lines.append("- gap `__StackLimit - __HeapLimit`: {} B".format(limits["heap_to_stack_gap_bytes"]))
    # Account for COPY reservations separately from ELF ALLOC sections.
    # Linker --print-memory-usage may stop at the .heap starting address,
    # whereas the explicitly positioned .stack is near the end of APP_DATA.
    required = ("__HeapBase", "__HeapLimit", "__StackLimit", "__StackTop")
    if all(k in limits["addresses"] for k in required):
        bounds = {k: int(limits["addresses"][k], 16) for k in required}
        app_region = report["regions"]["CM55M_S_APP_DATA"]
        origin = int(app_region["origin"], 16)
        end = int(app_region["end_exclusive"], 16)
        sections_sum = app_region["section_allocated_bytes_sum"]
        before_heap = bounds["__HeapBase"] - origin
        heap_bytes = bounds["__HeapLimit"] - bounds["__HeapBase"]
        stack_bytes = bounds["__StackTop"] - bounds["__StackLimit"]
        gap_bytes = bounds["__StackLimit"] - bounds["__HeapLimit"]
        tail_bytes = end - bounds["__StackTop"]
        accounting_gap = before_heap - sections_sum
        if min(before_heap, heap_bytes, stack_bytes, gap_bytes, tail_bytes, accounting_gap) >= 0:
            reserved = sections_sum + accounting_gap + heap_bytes + stack_bytes
            lines.extend(["", "## APP_DATA: ALLOC vs linker COPY reservations", "",
                          "| Item | Bytes |", "|---|---:|",
                          "| ELF ALLOC sections (sum) | {} |".format(sections_sum),
                          "| Pre-heap alignment/other difference | {} |".format(accounting_gap),
                          "| Linker .heap COPY reservation | {} |".format(heap_bytes),
                          "| Linker .stack COPY reservation | {} |".format(stack_bytes),
                          "| **Static occupied/reserved** | **{} ({:.2f}%)** |".format(
                              reserved, 100.0 * reserved / (end - origin)),
                          "| Gap between heap and stack (not proven allocatable) | {} |".format(gap_bytes),
                          "| Tail after stack | {} |".format(tail_bytes)])
            if reserved + gap_bytes + tail_bytes != end - origin:
                lines.append("**WARNING:** APP_DATA accounting does not reconcile to region capacity.")
    lines.extend(["", "## Largest symbols (not additive due to aliases)", "",
                  "| Symbol | Address | Size (B) | Region |", "|---|---|---:|---|"])
    for s in report["largest_symbols"][:20]:
        lines.append("| `{}` | {} | {} | {} |".format(s["name"].replace("|", "\\|"), s["address"], s["size_bytes"], s["region"]))
    lines.extend(["", "## Limitations", ""])
    lines.extend("- " + w for w in report["warnings"])
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-dir", type=Path, required=True, help="Existing build-sscma-legacy artifact run")
    ap.add_argument("--tool-prefix", default="arm-none-eabi-", help="Binutils prefix (tests: empty)")
    ap.add_argument("--output-dir", type=Path, help="Defaults to <run-dir>/memory-audit")
    args = ap.parse_args()
    run_dir = args.run_dir.resolve()
    report, outputs = make_report(run_dir, args.tool_prefix)
    out = (args.output_dir or run_dir / "memory-audit").resolve()
    out.mkdir(parents=True, exist_ok=True)
    for name, item in outputs.items():
        (out / name).write_text(item, encoding="utf-8")
    (out / "memory-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (out / "memory-report.md").write_text(markdown(report), encoding="utf-8")
    print("ELF/MAP SHA-256: VERIFIED; no build, image generation, flash, or device I/O")
    print("Report:", out / "memory-report.md")
    print("JSON  :", out / "memory-report.json")
    print("Candidate heap symbols:", len(report["heap_symbols"]))


if __name__ == "__main__":
    main()
