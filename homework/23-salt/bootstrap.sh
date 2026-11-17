#!/usr/bin/env bash
set -euo pipefail

master_ip=${1:?master IP required}
minion_id=${2:?minion ID required}
install_master=${3:?master flag required}

if [[ $EUID -ne 0 ]]; then
  echo 'Run as root' >&2
  exit 1
fi
if [[ $minion_id != web1 && $minion_id != web2 ]]; then
  echo 'minion ID must be web1 or web2' >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v salt-minion >/dev/null || { [[ $install_master == true ]] && ! command -v salt-master >/dev/null; }; then
  apt-get update
  apt-get install -y curl gnupg ca-certificates
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public |
    gpg --dearmor --yes --output /etc/apt/keyrings/salt-archive-keyring.pgp
  curl -fsSL https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.sources \
    > /etc/apt/sources.list.d/salt.sources
  cat > /etc/apt/preferences.d/salt-pin-1001 <<'EOF'
Package: salt-*
Pin: version 3008.*
Pin-Priority: 1001
EOF
  apt-get update
fi
if [[ $install_master == true ]]; then
  if ! command -v salt-master >/dev/null || ! command -v salt-minion >/dev/null; then
    apt-get install -y salt-master salt-minion
  fi
  install -d -m 0755 /etc/salt/master.d /srv/salt
  cat > /etc/salt/master.d/otus.conf <<'EOF'
file_roots:
  base:
    - /srv/salt
auto_accept: false
EOF
  cp -a /tmp/otus-salt/. /srv/salt/
  systemctl enable --now salt-master
  systemctl restart salt-master
else
  if ! command -v salt-minion >/dev/null; then
    apt-get install -y salt-minion
  fi
fi
install -d -m 0755 /etc/salt/minion.d
cat > /etc/salt/minion.d/otus.conf <<EOF
master: $master_ip
id: $minion_id
EOF
systemctl enable --now salt-minion
systemctl restart salt-minion
