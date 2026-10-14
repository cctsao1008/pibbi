"""Offline JSONL replay. Only local trace, state JSON and decision audit JSONL."""
import argparse
import json
import os
from pathlib import Path

from core import Core


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--trace", required=True, help="JSONL events with t (seconds) and kind")
    p.add_argument("--goal", default="Follow up one pending item")
    p.add_argument("--state", required=True, help="Local goal state JSON")
    p.add_argument("--audit", required=True, help="Append-only local decision audit JSONL")
    a = p.parse_args()

    state = Path(a.state)
    core = Core.restore(json.loads(state.read_text(encoding="utf-8"))) if state.exists() else Core(goal=a.goal)
    decisions = []
    for line in Path(a.trace).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        decisions.append(core.step(int(item["t"]), item["kind"]))

    audit = Path(a.audit)
    audit.parent.mkdir(parents=True, exist_ok=True)
    with audit.open("a", encoding="utf-8") as out:
        for item in decisions:
            out.write(json.dumps(item, ensure_ascii=False) + "\n")

    state.parent.mkdir(parents=True, exist_ok=True)
    tmp = state.with_suffix(state.suffix + ".tmp")
    tmp.write_text(json.dumps(core.snapshot(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, state)

    for item in decisions:
        print(json.dumps(item, ensure_ascii=False))


if __name__ == "__main__":
    main()
