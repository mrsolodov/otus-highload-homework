#!/usr/bin/env python3
"""Collect only credential reload events from both Nomad allocations."""

import json
import pathlib
import subprocess


root = pathlib.Path(__file__).resolve().parent.parent
allocations = json.loads(subprocess.check_output(
    ["nomad", "job", "allocs", "-json", "otus-portal"], text=True
))
lines = []
for allocation in allocations:
    if allocation["ClientStatus"] != "running":
        continue
    alloc_id = allocation["ID"]
    logs = subprocess.check_output(
        ["nomad", "alloc", "logs", "-stderr", alloc_id, "portal"], text=True
    )
    lines.append(f"Allocation {alloc_id[:8]}:")
    lines.extend(
        line for line in logs.splitlines()
        if "db credentials loaded user_fingerprint=" in line
    )
    lines.append("")
output = "\n".join(lines)
(root / "evidence" / "portal-logs.txt").write_text(output, encoding="utf-8")
print(output)
