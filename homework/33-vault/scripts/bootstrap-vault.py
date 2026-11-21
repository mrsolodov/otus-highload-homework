#!/usr/bin/env python3
"""Initialize the lab Raft cluster without printing unseal keys or root tokens."""

import json
import os
import pathlib
import subprocess
import time
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parent.parent
INIT_FILE = pathlib.Path.home() / ".otus33-vault-init.json"


def run_vault(node, *arguments, capture=False):
    return subprocess.run(
        [
            "docker", "compose", "exec", "-T", node,
            "env", "VAULT_ADDR=http://127.0.0.1:8200", "vault", *arguments,
        ],
        cwd=ROOT,
        check=True,
        capture_output=capture,
        text=True,
    )


def seal_status(port):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/sys/seal-status", timeout=15) as response:
        return json.load(response)


def unseal(port, key):
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/sys/unseal",
        data=json.dumps({"key": key}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        json.load(response)
    for _ in range(30):
        if not seal_status(port)["sealed"]:
            return
        time.sleep(1)
    raise RuntimeError(f"Vault on port {port} is still sealed")


if INIT_FILE.exists():
    result = json.loads(INIT_FILE.read_text(encoding="utf-8"))
else:
    result = json.loads(
        run_vault("vault1", "operator", "init", "-format=json", "-key-shares=1", "-key-threshold=1", capture=True).stdout
    )
    fd = os.open(INIT_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        json.dump(result, output)

key = result["unseal_keys_b64"][0]
if seal_status(8200)["sealed"]:
    unseal(8200, key)
print("vault1 initialized and unsealed", flush=True)
for node, port in (("vault2", 8202), ("vault3", 8204)):
    if not seal_status(port)["initialized"]:
        run_vault(node, "operator", "raft", "join", "http://vault1:8200", capture=True)
    if seal_status(port)["sealed"]:
        unseal(port, key)
    print(f"{node} joined and unsealed", flush=True)
print(f"Initialization material saved in {INIT_FILE} (mode 0600)", flush=True)
