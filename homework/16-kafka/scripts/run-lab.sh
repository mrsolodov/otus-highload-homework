#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")/.."
export COMPOSE_PROJECT_NAME=otus_kafka16
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
exec > >(tee evidence/cluster-check.txt) 2>&1

wait_for() {
  local description="$1" attempts="$2"
  shift 2
  for (( i=1; i<=attempts; i++ )); do
    if "$@" >/dev/null 2>&1; then
      echo "$description: ready after $i checks"
      return
    fi
    sleep 3
  done
  echo "$description: timed out" >&2
  "$@" || true
  docker compose ps || true
  docker compose logs --no-color --tail=80 kafka logstash-ingest logstash-indexer filebeat || true
  curl -fsS "$ES/_cat/indices/otus-web-*?v" || true
  return 1
}

echo "=== Start Elasticsearch and Kafka ==="
docker compose up -d es1 es2 es3 kafka
wait_for "Elasticsearch cluster" 120 python3 scripts/check-ready.py cluster 3
wait_for "Kafka broker" 100 docker compose exec -T kafka kafka-broker-api-versions --bootstrap-server kafka:9092
docker compose exec -T kafka kafka-topics --bootstrap-server kafka:9092 \
  --create --if-not-exists --topic otus-web-logs --partitions 3 --replication-factor 1
docker compose exec -T kafka kafka-topics --bootstrap-server kafka:9092 \
  --describe --topic otus-web-logs

echo "=== Configure Elasticsearch index ==="
curl -fsS -X PUT "$ES/_index_template/otus-web" \
  -H 'Content-Type: application/json' \
  --data-binary @elasticsearch/index-template.json
echo

echo "=== Start Nginx, Filebeat, two Logstash stages and Kibana ==="
docker compose up -d logstash-ingest logstash-indexer web1 web2 filebeat kibana
wait_for "Web frontend 1" 40 curl -fsS http://127.0.0.1:18081/
wait_for "Web frontend 2" 40 curl -fsS http://127.0.0.1:18082/
wait_for "Kibana" 120 python3 scripts/check-ready.py kibana
for i in {1..12}; do
  curl -fsS "http://127.0.0.1:18081/initial?id=$i" >/dev/null
  curl -fsS "http://127.0.0.1:18082/initial?id=$i" >/dev/null
done
wait_for "Initial events from both sources" 90 python3 scripts/assert-state.py --nodes 3 --minimum 12 --buffered 0
python3 scripts/assert-state.py --nodes 3 --minimum 12 --buffered 0

echo "=== Set up Kibana Discover ==="
curl -fsS -X POST "$KIBANA/api/data_views/data_view" \
  -H 'kbn-xsrf: otus-lab' -H 'Content-Type: application/json' \
  --data '{"data_view":{"id":"otus-web-logs","name":"OTUS web logs","title":"otus-web-*","timeFieldName":"@timestamp"},"override":true}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["data_view"]["id"]=="otus-web-logs"; print("Kibana data view:",d["data_view"]["title"])'

echo "=== Stop Kafka consumer and queue new requests ==="
docker compose stop logstash-indexer
offset_before="$(python3 scripts/kafka-offset.py)"
echo "Kafka end offset before buffered requests: $offset_before"
for i in {1..6}; do
  curl -fsS "http://127.0.0.1:18081/buffered?id=$i" >/dev/null
  curl -fsS "http://127.0.0.1:18082/buffered?id=$i" >/dev/null
done
wait_for "Twelve new events in Kafka" 90 python3 scripts/kafka-offset.py "$((offset_before + 12))"
offset_after="$(python3 scripts/kafka-offset.py)"
echo "Kafka end offset while consumer is stopped: $offset_after"
python3 scripts/assert-state.py --nodes 3 --minimum 12 --buffered 0

echo "=== Restart consumer and verify delayed delivery ==="
docker compose start logstash-indexer
wait_for "Buffered logs indexed" 90 python3 scripts/assert-state.py --nodes 3 --minimum 18 --buffered 6
python3 scripts/assert-state.py --nodes 3 --minimum 18 --buffered 6
echo "Checks passed. Kafka retained events while the consumer was stopped."
