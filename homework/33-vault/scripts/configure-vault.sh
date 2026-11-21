#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VAULT_TOKEN:?Set VAULT_TOKEN from vault operator init}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD from .env}"
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

vault status >/dev/null
if ! vault secrets list -format=json | grep -q '"database/"'; then
  vault secrets enable database
fi
vault write database/config/portal \
  plugin_name=postgresql-database-plugin \
  allowed_roles=portal \
  connection_url='postgresql://{{username}}:{{password}}@postgres:5432/portal?sslmode=disable' \
  username=vault_admin \
  password="$POSTGRES_PASSWORD"
vault write database/roles/portal \
  db_name=portal \
  creation_statements=@vault/portal.sql \
  revocation_statements='DROP OWNED BY "{{name}}"; DROP ROLE IF EXISTS "{{name}}";' \
  default_ttl=120s \
  max_ttl=120s
if ! vault auth list -format=json | grep -q '"jwt-nomad/"'; then
  vault auth enable -path=jwt-nomad jwt
fi
vault write auth/jwt-nomad/config @vault/jwt-config.json
vault policy write portal-db vault/portal-policy.hcl
vault write auth/jwt-nomad/role/portal @vault/portal-role.json
echo 'Vault database role and Nomad JWT role configured.'
