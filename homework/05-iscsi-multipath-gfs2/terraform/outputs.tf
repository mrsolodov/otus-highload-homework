output "iscsi_target_public_ip" {
  description = "Public IP address of the iSCSI target"
  value       = yandex_compute_instance.iscsi_target.network_interface[0].nat_ip_address
}

output "iscsi_target_private_ips" {
  description = "Private addresses of both iSCSI paths"

  value = {
    path_a = yandex_compute_instance.iscsi_target.network_interface[0].ip_address
    path_b = yandex_compute_instance.iscsi_target.network_interface[1].ip_address
  }
}

output "gfs_node_public_ips" {
  description = "Public IP addresses of GFS2 nodes"

  value = {
    for name, instance in yandex_compute_instance.gfs_node :
    name => instance.network_interface[0].nat_ip_address
  }
}

output "gfs_node_private_ips" {
  description = "Private addresses of GFS2 nodes"

  value = {
    for name, instance in yandex_compute_instance.gfs_node :
    name => {
      path_a = instance.network_interface[0].ip_address
      path_b = instance.network_interface[1].ip_address
    }
  }
}

output "ansible_inventory" {
  description = "Generated Ansible inventory"

  value = <<-EOT
[iscsi_target]
gfs-target ansible_host=${yandex_compute_instance.iscsi_target.network_interface[0].nat_ip_address} path_a_ip=10.50.11.10 path_b_ip=10.50.12.10

[gfs_nodes]
gfs1 ansible_host=${yandex_compute_instance.gfs_node["gfs1"].network_interface[0].nat_ip_address} cluster_ip=10.50.1.21 path_a_ip=10.50.1.21 path_b_ip=10.50.2.21
gfs2 ansible_host=${yandex_compute_instance.gfs_node["gfs2"].network_interface[0].nat_ip_address} cluster_ip=10.50.11.22 path_a_ip=10.50.11.22 path_b_ip=10.50.12.22
gfs3 ansible_host=${yandex_compute_instance.gfs_node["gfs3"].network_interface[0].nat_ip_address} cluster_ip=10.50.1.23 path_a_ip=10.50.1.23 path_b_ip=10.50.2.23

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
EOT
}

output "deployment_layout" {
  description = "Virtual machine placement by availability zone"

  value = {
    ru-central1-d = ["gfs1", "gfs3"]
    ru-central1-e = ["gfs-target", "gfs2"]
  }
}