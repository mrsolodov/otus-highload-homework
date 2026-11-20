#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=${BACKUP_DIR:-/var/backups/otus-k3s}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# These exports are useful for inspection. The database copy is the restore source.
kubectl get all --all-namespaces -o yaml > "$work/all-resources.yaml"
kubectl get configmaps,secrets,ingresses,persistentvolumeclaims,serviceaccounts,roles,rolebindings -A -o yaml > "$work/config-and-access.yaml"
kubectl get namespaces,nodes,persistentvolumes,clusterroles,clusterrolebindings,storageclasses,ingressclasses -o yaml > "$work/cluster-resources.yaml"
mkdir -p "$work/server-db" "$work/server-config"
sqlite3 /var/lib/rancher/k3s/server/db/state.db ".backup '$work/server-db/state.db'"
cp /var/lib/rancher/k3s/server/token "$work/server-config/token"
if [ -d /etc/rancher/k3s ]; then cp -a /etc/rancher/k3s/. "$work/server-config/"; fi
k3s --version > "$work/version.txt"
tar -C "$work" -czf "$BACKUP_DIR/cluster-$stamp.tar.gz" .
chmod 600 "$BACKUP_DIR/cluster-$stamp.tar.gz"
sha256sum "$BACKUP_DIR/cluster-$stamp.tar.gz" > "$BACKUP_DIR/cluster-$stamp.tar.gz.sha256"
chmod 600 "$BACKUP_DIR/cluster-$stamp.tar.gz.sha256"
echo "$BACKUP_DIR/cluster-$stamp.tar.gz"
