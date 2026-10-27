#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p evidence

query() {
    local node="$1" sql="$2"
    printf '%s\n' "$sql" | docker compose exec -T "$node" \
        sh -c 'MYSQL_PWD=$(cat /run/secrets/mysql_root_password) exec mysql -h 127.0.0.1 -uroot -N -B'
}

status() {
    local node="$1" key="$2"
    query "$node" "SHOW GLOBAL STATUS LIKE '$key';" | awk -F '\t' -v k="$key" '$1 == k {print $2}'
}

wait_for_cluster() {
    local expected="$1" node="$2" i size primary ready synced
    for ((i=0; i<90; i++)); do
        size=$(status "$node" wsrep_cluster_size 2>/dev/null || true)
        primary=$(status "$node" wsrep_cluster_status 2>/dev/null || true)
        ready=$(status "$node" wsrep_ready 2>/dev/null || true)
        synced=$(status "$node" wsrep_local_state_comment 2>/dev/null || true)
        if [[ "$size" == "$expected" && "$primary" == Primary && "$ready" == ON && "$synced" == Synced ]]; then
            echo "$node: size=$size status=$primary ready=$ready state=$synced"
            return 0
        fi
        if docker compose ps --status exited --services | grep -Fxq "$node"; then
            echo "$node exited before joining the cluster" >&2
            docker compose logs --no-color --tail=300 "$node" >&2
            return 1
        fi
        sleep 4
    done
    echo "Timed out waiting for $node at cluster size $expected" >&2
    docker compose ps >&2
    return 1
}

assert_row() {
    local node="$1" id="$2" backend="$3" actual
    actual=$(query "$node" "SELECT backend FROM otusapp.requests WHERE id=$id;")
    [[ "$actual" == "$backend" ]] || { echo "Unexpected row $id on $node: $actual" >&2; return 1; }
    echo "$node: request id=$id backend=$actual"
}

./scripts/prepare.sh
docker compose config -q
docker compose up -d pxc1
wait_for_cluster 1 pxc1
docker compose up -d pxc2
wait_for_cluster 2 pxc1
wait_for_cluster 2 pxc2
docker compose up -d pxc3
for node in pxc1 pxc2 pxc3; do wait_for_cluster 3 "$node"; done

docker compose exec -T pxc1 sh -c \
    'MYSQL_PWD=$(cat /run/secrets/mysql_root_password) exec mysql -h 127.0.0.1 -uroot' < sql/otusapp.sql
query pxc1 "INSERT INTO otusapp.requests(id, backend) VALUES (1001, 'app1') ON DUPLICATE KEY UPDATE backend=VALUES(backend);" >/dev/null
for node in pxc1 pxc2 pxc3; do assert_row "$node" 1001 app1; done

echo 'Stopping pxc2 to verify quorum and writes on surviving nodes.'
docker compose stop pxc2
wait_for_cluster 2 pxc1
wait_for_cluster 2 pxc3
query pxc3 "INSERT INTO otusapp.requests(id, backend) VALUES (1002, 'app2') ON DUPLICATE KEY UPDATE backend=VALUES(backend);" >/dev/null
assert_row pxc1 1002 app2

docker compose start pxc2
for node in pxc1 pxc2 pxc3; do
    wait_for_cluster 3 "$node"
    assert_row "$node" 1001 app1
    assert_row "$node" 1002 app2
done

{
    echo 'PXC cluster verification'
    echo 'Schema: otusapp.requests (same logical table as homework 07)'
    echo 'All nodes: Primary / Synced / ready ON / size 3'
    echo 'After pxc2 stopped: surviving nodes Primary / Synced / size 2'
    echo 'Write to pxc3 while pxc2 stopped: visible on pxc1'
    echo 'After pxc2 restarted: both test rows visible on every node'
    for node in pxc1 pxc2 pxc3; do
        printf '%s: ' "$node"
        query "$node" 'SELECT COUNT(*) FROM otusapp.requests WHERE id IN (1001,1002);'
    done
} | tee evidence/cluster-check.txt

if [[ "${1:-}" == --destroy ]]; then
    docker compose down -v
    echo 'Containers and their lab volumes were removed.'
fi
