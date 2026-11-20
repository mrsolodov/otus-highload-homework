#!/usr/bin/env bash
set -euo pipefail

: "${K3S_TOKEN:?K3S_TOKEN is required}"
SERVER_IP=${SERVER_IP:-172.28.19.10}
AGENT_IP=${AGENT_IP:-172.28.19.11}

systemctl disable --now nginx 2>/dev/null || true
iptables -I INPUT 1 -p tcp -s 172.28.19.0/24 --dport 10250 -j ACCEPT
iptables -I INPUT 1 -p udp -s 172.28.19.0/24 --dport 8472 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
netfilter-persistent save

curl -sfL https://get.k3s.io | K3S_URL="https://${SERVER_IP}:6443" K3S_TOKEN="$K3S_TOKEN" sh -s - agent --node-ip "$AGENT_IP"
systemctl is-active --quiet k3s-agent
