#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
umask 077
mkdir -p secrets certs

for name in mysql_root_password xtrabackup_password; do
    if [[ ! -s "secrets/$name" ]]; then
        openssl rand -hex 24 > "secrets/$name"
    fi
done

if [[ ! -f certs/ca.pem || ! -f certs/server-cert.pem || ! -f certs/server-key.pem ]]; then
    if [[ -e certs/ca.pem || -e certs/server-cert.pem || -e certs/server-key.pem ]]; then
        echo 'Incomplete certificate set. Inspect certs/ before proceeding.' >&2
        exit 1
    fi
    openssl req -new -x509 -nodes -days 365 \
        -newkey rsa:2048 -keyout certs/ca-key.pem -out certs/ca.pem \
        -subj '/CN=OTUS PXC Lab CA' >/dev/null 2>&1
    openssl req -new -nodes -newkey rsa:2048 \
        -keyout certs/server-key.pem -out certs/server-req.pem \
        -subj '/CN=pxc-node' >/dev/null 2>&1
    openssl x509 -req -days 365 -in certs/server-req.pem \
        -CA certs/ca.pem -CAkey certs/ca-key.pem -CAcreateserial \
        -out certs/server-cert.pem >/dev/null 2>&1
fi

# The container reads the public certificates and the server key through a
# read-only mount; these files are generated only for this isolated lab.
chmod 644 certs/ca.pem certs/server-cert.pem
chmod 644 certs/server-key.pem
echo 'Local secrets and lab certificates are ready.'
