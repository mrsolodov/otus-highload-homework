#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")/.."
export COMPOSE_PROJECT_NAME=otus_consul16

if [[ "${1:-}" == "--destroy" ]]; then
  docker compose down -v --remove-orphans
  exit
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: bash scripts/run-lab.sh [--destroy]" >&2
  exit 2
fi

mkdir -p evidence
exec > >(tee evidence/lab-run.txt) 2>&1

wait_for() {
  local label="$1" phase="$2"
  for ((attempt=1; attempt<=75; attempt++)); do
    if python3 scripts/verify.py --phase "$phase"; then
      echo "$label: passed on attempt $attempt"
      return 0
    fi
    sleep 2
  done
  echo "$label: timed out" >&2
  docker compose ps || true
  docker compose logs --no-color --tail=70 consul1 consul2 consul3 web1-agent web2-agent || true
  return 1
}

echo '=== Start three Consul servers, two web servers and their agents ==='
docker compose up -d consul1 consul2 consul3 web1 web2 web1-agent web2-agent
wait_for 'All nodes and both DNS records' initial

echo '=== Stop web2: its IP must disappear from portal.service.consul ==='
docker compose stop web2
wait_for 'Only web1 remains in healthy DNS' web2-down

echo '=== Restore web2: its IP must return ==='
docker compose start web2
wait_for 'Both DNS records returned' restored

echo '=== Stop consul1: query second server with quorum of two ==='
docker compose stop consul1
wait_for 'Second Consul server serves DNS' consul1-down

echo '=== Restore consul1 ==='
docker compose start consul1
wait_for 'All nodes and both DNS records restored' initial
echo 'Checks passed: health-filtered DNS and Consul server failover.'
