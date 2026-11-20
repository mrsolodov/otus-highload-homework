#!/usr/bin/env bash
set -euo pipefail

SERVER_IP=${SERVER_IP:-172.28.19.10}
export DEBIAN_FRONTEND=noninteractive

# The previous Salt exercise leaves Nginx on port 80 and INPUT policy DROP.
systemctl disable --now nginx 2>/dev/null || true
iptables -I INPUT 1 -p tcp -s 172.28.19.0/24 --dport 6443 -j ACCEPT
iptables -I INPUT 1 -p tcp -s 172.28.19.0/24 --dport 10250 -j ACCEPT
iptables -I INPUT 1 -p udp -s 172.28.19.0/24 --dport 8472 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
netfilter-persistent save

curl -sfL https://get.k3s.io | sh -s - server --node-ip "$SERVER_IP" --tls-san "$SERVER_IP"
systemctl is-active --quiet k3s
for attempt in {1..30}; do
  if kubectl get nodes >/dev/null 2>&1; then break; fi
  sleep 2
done
kubectl get nodes -o wide
