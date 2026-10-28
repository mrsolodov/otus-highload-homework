#!/usr/bin/env bash
set -euo pipefail

root=$1
mkdir -p "$root/ansible/.secrets" "$HOME/.ssh/otus-10"
chmod 700 "$HOME/.ssh" "$HOME/.ssh/otus-10"

for vm in nginx1 nginx2 app1 app2 db1; do
    cp "$root/.vagrant/machines/$vm/virtualbox/private_key" "$HOME/.ssh/otus-10/$vm"
    chmod 600 "$HOME/.ssh/otus-10/$vm"
done

if [[ ! -s "$root/ansible/.secrets/db-password" ]]; then
    python3 -c 'import secrets,sys; sys.stdout.write(secrets.token_hex(24) + "\n")' > "$root/ansible/.secrets/db-password"
    chmod 600 "$root/ansible/.secrets/db-password"
fi

if timeout 3 bash -c ': > /dev/tcp/192.168.56.11/22' 2>/dev/null; then
    python3 - "$root/ansible/inventory.ini" "$root/ansible/inventory.local.ini" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
lines = []
for line in source.splitlines():
    match = re.search(r"\bprivate_ip=(\d+\.\d+\.\d+\.\d+)", line)
    if match:
        line = re.sub(r"ansible_host=127\.0\.0\.1 ansible_port=\d+", f"ansible_host={match.group(1)} ansible_port=22", line)
    lines.append(line)
Path(sys.argv[2]).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
elif timeout 3 bash -c ': > /dev/tcp/127.0.0.1/2211' 2>/dev/null; then
    cp "$root/ansible/inventory.ini" "$root/ansible/inventory.local.ini"
else
    echo "WSL cannot reach Vagrant SSH via private IP or local forwarded port." >&2
    exit 1
fi
