#!/usr/bin/env bash
set -euo pipefail

install -m 700 /tmp/otus-k8s/scripts/backup-cluster.sh /usr/local/sbin/otus-k3s-backup
cat >/etc/systemd/system/otus-k3s-backup.service <<'EOF'
[Unit]
Description=Back up the OTUS K3s cluster
After=k3s.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/otus-k3s-backup
EOF
cat >/etc/systemd/system/otus-k3s-backup.timer <<'EOF'
[Unit]
Description=Daily OTUS K3s cluster backup
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now otus-k3s-backup.timer
systemctl start otus-k3s-backup.service
systemctl status otus-k3s-backup.timer --no-pager
