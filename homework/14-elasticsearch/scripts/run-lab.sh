#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")/.."
export COMPOSE_PROJECT_NAME=otus_es14
ES=http://127.0.0.1:19200
KIBANA=http://127.0.0.1:15601

if [[ "${1:-}" == "--destroy" ]]; then
  docker compose down -v --remove-orphans
  exit
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: bash scripts/run-lab.sh [--destroy]" >&2
  exit 2
fi

mkdir -p evidence
rm -f evidence/cluster-check.txt
exec > >(tee evidence/cluster-check.txt) 2>&1

wait_for() {
  local description="$1" attempts="$2"
  shift 2
  for (( i=1; i<=attempts; i++ )); do
    if "$@" >/dev/null 2>&1; then
      echo "$description: ready after $i checks"
      return 0
    fi
    sleep 3
  done
  echo "$description: timed out" >&2
  "$@" || true
  docker compose ps || true
  docker compose logs --no-color --tail=80 filebeat web1 web2 || true
  curl -fsS "$ES/_cat/indices/otus-web-*?v" || true
  return 1
}

echo "=== Start Elasticsearch ==="
docker compose up -d es1 es2 es3
wait_for "Three-node cluster" 120 python3 scripts/check-ready.py cluster 3

echo "=== Index template: one primary and one replica ==="
curl -fsS -X PUT "$ES/_index_template/otus-web" \
  -H 'Content-Type: application/json' \
  --data-binary @elasticsearch/index-template.json
echo

echo "=== Start two frontends, Filebeat and Kibana ==="
docker compose up -d web1 web2 filebeat kibana
wait_for "Web frontend 1" 40 curl -fsS http://127.0.0.1:18081/
wait_for "Web frontend 2" 40 curl -fsS http://127.0.0.1:18082/
wait_for "Kibana" 120 python3 scripts/check-ready.py kibana

echo "=== Generate access logs on both web nodes ==="
for i in {1..12}; do
  curl -fsS "http://127.0.0.1:18081/requests?id=$i" >/dev/null
  curl -fsS "http://127.0.0.1:18082/requests?id=$i" >/dev/null
done
wait_for "Both frontends indexed" 60 python3 scripts/assert-state.py --nodes 3 --minimum 12
python3 scripts/assert-state.py --nodes 3 --minimum 12

echo "=== Create Kibana data view for Discover ==="
curl -fsS -X POST "$KIBANA/api/data_views/data_view" \
  -H 'kbn-xsrf: otus-lab' \
  -H 'Content-Type: application/json' \
  --data '{"data_view":{"id":"otus-web-logs","name":"OTUS web logs","title":"otus-web-*","timeFieldName":"@timestamp"},"override":true}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["data_view"]["id"]=="otus-web-logs"; print("Kibana data view:", d["data_view"]["title"])'
curl -fsS -H 'kbn-xsrf: otus-lab' "$KIBANA/api/data_views/data_view/otus-web-logs" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["data_view"]["title"]=="otus-web-*"; print("Discover data view is available")'

echo "=== Stop a node holding a replica or primary shard ==="
FAILED_NODE="$(curl -fsS "$ES/_cat/shards/otus-web-*?format=json" | python3 -c 'import json,sys; rows=json.load(sys.stdin); nodes={r["node"] for r in rows}; candidates=nodes-{"es1"}; assert candidates, rows; print(sorted(candidates)[0])')"
echo "Stopped node: $FAILED_NODE"
docker compose stop "$FAILED_NODE"
wait_for "Cluster recovered with two nodes" 80 python3 scripts/check-ready.py cluster 2
for i in {13..16}; do
  curl -fsS "http://127.0.0.1:18081/after-failure?id=$i" >/dev/null
  curl -fsS "http://127.0.0.1:18082/after-failure?id=$i" >/dev/null
done
wait_for "Logs continue while one node is down" 60 python3 scripts/assert-state.py --nodes 2 --minimum 16
python3 scripts/assert-state.py --nodes 2 --minimum 16

echo "=== Restore Elasticsearch node ==="
docker compose start "$FAILED_NODE"
wait_for "Three-node cluster restored" 80 python3 scripts/check-ready.py cluster 3
python3 scripts/assert-state.py --nodes 3 --minimum 16
echo "Checks passed. Logs: http://127.0.0.1:15601/app/discover"
