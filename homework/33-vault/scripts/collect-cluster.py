#!/usr/bin/env python3
"""Write a secret-free snapshot of the running lab."""

import json
import os
import pathlib
import subprocess


root = pathlib.Path(__file__).resolve().parent.parent
init = json.loads((pathlib.Path.home() / ".otus33-vault-init.json").read_text(encoding="utf-8"))
environment = dict(os.environ, VAULT_ADDR="http://127.0.0.1:8200", VAULT_TOKEN=init["root_token"])
peers = subprocess.check_output(["vault", "operator", "raft", "list-peers"], env=environment, text=True)
role = json.loads(subprocess.check_output(
    ["vault", "read", "-format=json", "database/roles/portal"], env=environment, text=True
))["data"]
allocations = subprocess.check_output(["nomad", "job", "allocs", "otus-portal"], text=True)
services = subprocess.check_output(["nomad", "service", "info", "otus-portal"], text=True)
output = (
    "Vault Raft peers:\n" + peers + "\n"
    + f"Vault database role: default_ttl={role['default_ttl']} max_ttl={role['max_ttl']}\n\n"
    + "Nomad allocations:\n" + allocations + "\n"
    + "Nomad services:\n" + services
)
destination = root / "evidence" / "cluster.txt"
destination.write_text(output, encoding="utf-8")
print(output)
