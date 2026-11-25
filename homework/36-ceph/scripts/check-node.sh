#!/usr/bin/env bash
set -euo pipefail

echo "host=$(hostname)"
echo "time=$(date -Is)"
echo "memory_mib=$(awk '/MemTotal/ { print int($2 / 1024) }' /proc/meminfo)"
echo "container_runtime=$(command -v podman || command -v docker || true)"
echo "lvm=$(command -v lvm || true)"
echo "time_sync=$(timedatectl show -p NTPSynchronized --value)"
echo "ip_addresses:"
ip -brief address
echo "block_devices:"
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS
echo "osd_candidate_details:"
if [[ -b /dev/vdb ]]; then
  lsblk -nr -o NAME,TYPE,FSTYPE,MOUNTPOINTS /dev/vdb
  sudo wipefs -n /dev/vdb
else
  echo "/dev/vdb is absent; find the dedicated empty OSD disk manually"
fi
