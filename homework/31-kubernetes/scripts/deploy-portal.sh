#!/usr/bin/env bash
set -euo pipefail

: "${PORTAL_PASSWORD:?Set a portal password before deployment}"
MANIFEST_DIR=${1:-/tmp/otus-k8s/manifests}
command -v openssl >/dev/null

kubectl apply -f "$MANIFEST_DIR/00-namespace.yaml"
hash=$(openssl passwd -apr1 "$PORTAL_PASSWORD")
printf 'otus:%s\n' "$hash" | kubectl -n otus-portal create secret generic portal-auth \
  --from-file=htpasswd=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$MANIFEST_DIR"
kubectl -n otus-portal rollout status deployment/portal --timeout=180s
kubectl -n otus-portal get deployment,service,ingress,pods -o wide
