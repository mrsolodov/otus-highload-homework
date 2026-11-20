#!/usr/bin/env bash
set -euo pipefail
IFS= read -r K3S_TOKEN
K3S_TOKEN=${K3S_TOKEN%$'\r'}
export K3S_TOKEN
exec bash /tmp/otus-k8s/scripts/bootstrap-agent.sh
