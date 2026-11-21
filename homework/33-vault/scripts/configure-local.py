#!/usr/bin/env python3
"""Configure this lab using locally stored initialization material."""

import json
import os
import pathlib
import subprocess


root = pathlib.Path(__file__).resolve().parent.parent
init_file = pathlib.Path.home() / ".otus33-vault-init.json"
init = json.loads(init_file.read_text(encoding="utf-8"))
settings = dict(
    line.split("=", 1)
    for line in (root / ".env").read_text(encoding="utf-8").splitlines()
    if line and not line.startswith("#")
)
environment = dict(
    os.environ,
    VAULT_ADDR="http://127.0.0.1:8200",
    VAULT_TOKEN=init["root_token"],
    POSTGRES_PASSWORD=settings["POSTGRES_PASSWORD"],
)
subprocess.run(["bash", "scripts/configure-vault.sh"], cwd=root, env=environment, check=True)
