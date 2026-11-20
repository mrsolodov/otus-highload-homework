#!/usr/bin/env bash
set -euo pipefail
IFS= read -r PORTAL_PASSWORD
PORTAL_PASSWORD=${PORTAL_PASSWORD%$'\r'}
export PORTAL_PASSWORD
exec bash /tmp/otus-k8s/scripts/deploy-portal.sh
