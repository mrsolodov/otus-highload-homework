#!/usr/bin/env bash
set -euo pipefail

lab_dir=/tmp/otus10
mkdir -p "$lab_dir"
curl --fail --location --retry 3 --output "$lab_dir/ubuntu.qcow2" \
  https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
ssh-keygen -q -t ed25519 -N '' -f "$lab_dir/id_ed25519"
chmod 755 "$lab_dir"
chown "$SUDO_UID:$SUDO_GID" "$lab_dir/id_ed25519" "$lab_dir/id_ed25519.pub"
cat > "$lab_dir/network.xml" <<'EOF'
<network>
  <name>otus10</name>
  <forward mode='nat'/>
  <ip address='192.168.56.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.56.100' end='192.168.56.199'/>
      <host mac='52:54:00:10:00:11' ip='192.168.56.11'/>
      <host mac='52:54:00:10:00:12' ip='192.168.56.12'/>
      <host mac='52:54:00:10:00:21' ip='192.168.56.21'/>
      <host mac='52:54:00:10:00:22' ip='192.168.56.22'/>
      <host mac='52:54:00:10:00:30' ip='192.168.56.30'/>
    </dhcp>
  </ip>
</network>
EOF
virsh net-define "$lab_dir/network.xml"
virsh net-start otus10

for spec in nginx1:11:768 nginx2:12:768 app1:21:2048 app2:22:2048 db1:30:2048; do
  IFS=: read -r name suffix memory <<< "$spec"
  qemu-img create -f qcow2 -F qcow2 -b "$lab_dir/ubuntu.qcow2" "$lab_dir/$name.qcow2" 12G
  cat > "$lab_dir/$name-user-data" <<EOF
#cloud-config
hostname: $name
manage_etc_hosts: true
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$lab_dir/id_ed25519.pub")
ssh_pwauth: false
EOF
  cloud-localds "$lab_dir/$name-seed.iso" "$lab_dir/$name-user-data"
  virt-install --connect qemu:///system --name "otus10-$name" --memory "$memory" --vcpus 1 \
    --os-variant ubuntu24.04 --import --disk "path=$lab_dir/$name.qcow2,format=qcow2" \
    --disk "path=$lab_dir/$name-seed.iso,device=cdrom" \
    --network "network=otus10,mac=52:54:00:10:00:$suffix" \
    --graphics none --noautoconsole
done

virsh list --all
for spec in nginx1:11 nginx2:12 app1:21 app2:22 db1:30; do
  IFS=: read -r name suffix <<< "$spec"
  ip="192.168.56.$((10#$suffix))"
  echo "Waiting for $name ($ip)"
  for attempt in $(seq 1 75); do
    if ssh -i "$lab_dir/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 "ubuntu@$ip" \
      'cloud-init status --wait; true'; then break; fi
    if (( attempt == 75 )); then echo "$name did not become ready" >&2; exit 1; fi
    sleep 3
  done
done

python3 - "$lab_dir" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path.cwd()
source = (root / 'ansible/inventory.ini').read_text()
for name, ip in [('nginx1','11'),('nginx2','12'),('app1','21'),('app2','22'),('db1','30')]:
    source = re.sub(rf'(?m)^{name} ansible_host=127\.0\.0\.1 ansible_port=\d+',
                    f'{name} ansible_host=192.168.56.{ip}', source)
    source = source.replace(f'ansible_ssh_private_key_file=~/.ssh/otus-10/{name}',
                            f'ansible_ssh_private_key_file={sys.argv[1]}/id_ed25519')
source = source.replace('ansible_user=vagrant', 'ansible_user=ubuntu')
(root / 'ansible/inventory.ci.ini').write_text(source)
PY
