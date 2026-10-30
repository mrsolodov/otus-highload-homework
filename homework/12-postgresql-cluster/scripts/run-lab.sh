#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
umask 077

if [[ ! -f .env ]]; then
  command -v openssl >/dev/null || { echo 'OpenSSL is required' >&2; exit 1; }
  printf 'POSTGRES_PASSWORD=%s\nREPLICATION_PASSWORD=%s\n' \
    "$(openssl rand -hex 24)" "$(openssl rand -hex 24)" > .env
fi

mkdir -p evidence
rm -f evidence/cluster-check.txt
docker compose up -d --build

nodes=(pg1 pg2 pg3)
leader=''
alive=()

is_primary() {
  docker compose exec -T "$1" curl --silent --fail --max-time 3 \
    http://127.0.0.1:8008/primary >/dev/null 2>&1
}

wait_members() {
  local expected="$1" attempts node candidate count
  for ((attempts=0; attempts<120; attempts++)); do
    alive=()
    leader=''
    for node in "${nodes[@]}"; do
      if [[ "$(docker compose ps --status running --services)" != *"$node"* ]]; then
        continue
      fi
      if docker compose exec -T "$node" curl --silent --fail --max-time 3 \
        http://127.0.0.1:8008/health >/dev/null 2>&1; then
        alive+=("$node")
        if is_primary "$node"; then
          leader="$node"
        fi
      fi
    done
    count="${#alive[@]}"
    if [[ "$count" -eq "$expected" && -n "$leader" ]]; then
      return 0
    fi
    sleep 3
  done
  echo "Timed out: expected $expected PostgreSQL members and one primary (found ${#alive[@]}, primary $leader)" >&2
  docker compose ps >&2
  return 1
}

query() {
  local client="$1" host="$2" sql="$3"
  timeout 15s docker compose exec -T "$client" sh -c \
    'PGPASSWORD="$PATRONI_SUPERUSER_PASSWORD" PGCONNECT_TIMEOUT=5 PGOPTIONS="-c statement_timeout=5000" psql -XAt -v ON_ERROR_STOP=1 -h "$1" -U postgres -d postgres -c "$2"' \
    sh "$host" "$sql" | tr -d '\r'
}

wait_write_route() {
  local client="$1" attempts role
  for ((attempts=0; attempts<40; attempts++)); do
    if role="$(query "$client" haproxy 'SELECT pg_is_in_recovery()' 2>/dev/null)" \
        && [[ "$role" == f ]]; then
      return 0
    fi
    if (( attempts % 5 == 0 )); then
      echo "Waiting for HAProxy to route writes (attempt $((attempts + 1)))"
    fi
    sleep 2
  done
  echo 'HAProxy did not route writes to the primary' >&2
  return 1
}

wait_streaming() {
  local client="$1" expected="$2" attempts count
  for ((attempts=0; attempts<40; attempts++)); do
    if count="$(query "$client" "$client" "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'" 2>/dev/null)" \
        && [[ "$count" == "$expected" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "Expected $expected streaming replicas on $client; found ${count:-unknown}" >&2
  return 1
}

wait_rows() {
  local expected="$1" attempts node count
  for ((attempts=0; attempts<60; attempts++)); do
    count=0
    for node in "${alive[@]}"; do
      if [[ "$(query "$node" "$node" 'SELECT count(*) FROM otusapp.requests')" == "$expected" ]]; then
        ((count+=1))
      fi
    done
    if [[ "$count" -eq "${#alive[@]}" ]]; then return 0; fi
    sleep 2
  done
  echo "Rows did not replicate to all ${#alive[@]} nodes" >&2
  return 1
}

{
  wait_members 3
  first_leader="$leader"
  echo "Initial primary: $first_leader; PostgreSQL members: ${alive[*]}"
  for node in "${nodes[@]}"; do
    role="$(query "$node" "$node" 'SELECT pg_is_in_recovery()')"
    echo "$node in recovery: $role"
    if [[ "$node" == "$leader" ]]; then
      [[ "$role" == f ]]
    else
      [[ "$role" == t ]]
    fi
  done

  wait_streaming "$leader" 2
  wait_write_route "$leader"
  echo "Write route before failover: $(query "$leader" haproxy 'SELECT pg_is_in_recovery()')"

  query "$leader" haproxy 'CREATE SCHEMA IF NOT EXISTS otusapp' >/dev/null
  query "$leader" haproxy 'CREATE TABLE IF NOT EXISTS otusapp.requests (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, note text NOT NULL, created_at timestamptz NOT NULL DEFAULT now())' >/dev/null
  echo "Table after creation: $(query "$leader" haproxy "SELECT to_regclass('otusapp.requests')")"
  query "$leader" haproxy "INSERT INTO otusapp.requests (note) VALUES ('before failover')" >/dev/null
  wait_rows 1
  echo 'First write through HAProxy is visible on all nodes.'

  docker compose stop "$first_leader" >/dev/null
  echo "Stopped former primary: $first_leader"
  wait_members 2
  [[ "$leader" != "$first_leader" ]]
  echo "Promoted primary: $leader; remaining members: ${alive[*]}"
  wait_write_route "$leader"
  query "$leader" haproxy "INSERT INTO otusapp.requests (note) VALUES ('after failover')" >/dev/null
  wait_rows 2
  echo 'Second write through HAProxy is visible on both surviving nodes.'

  docker compose start "$first_leader" >/dev/null
  wait_members 3
  wait_rows 2
  [[ "$(query "$first_leader" "$first_leader" 'SELECT pg_is_in_recovery()')" == t ]]
  echo "Former primary $first_leader rejoined as a replica."
  echo "Current primary: $leader; rows on all nodes: 2"
  docker compose exec -T etcd1 /usr/local/bin/etcdctl \
    --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 endpoint health
  echo 'Verification passed.'
} | tee evidence/cluster-check.txt

if [[ "${1:-}" == '--destroy' ]]; then
  docker compose down -v
fi
