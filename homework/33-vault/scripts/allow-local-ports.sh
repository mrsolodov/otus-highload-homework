#!/usr/bin/env bash
set -euo pipefail

compose_subnet=$(docker network inspect otus33_default --format '{{(index .IPAM.Config 0).Subnet}}')
docker_subnet=$(ip -4 -o addr show docker0 | awk '{print $4}')

for rule in "$compose_subnet:4646" "$docker_subnet:5432"; do
  subnet=${rule%:*}
  port=${rule##*:}
  if ! sudo iptables -C INPUT -s "$subnet" -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT 1 -s "$subnet" -p tcp --dport "$port" -j ACCEPT
  fi
done
echo "Docker subnets can reach Nomad JWKS and PostgreSQL on the host."
