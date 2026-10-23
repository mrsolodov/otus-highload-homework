output "lb_url" {
  description = "Public URL of the Nginx load balancer"
  value       = "http://${yandex_compute_instance.node["lb"].network_interface[0].nat_ip_address}"
}

output "public_ips" {
  description = "Public IP addresses for SSH/Ansible access"
  value = {
    for name, vm in yandex_compute_instance.node :
    name => vm.network_interface[0].nat_ip_address
  }
}

output "private_ips" {
  description = "Private IP addresses for Nginx upstreams"
  value = {
    for name, vm in yandex_compute_instance.node :
    name => vm.network_interface[0].ip_address
  }
}

output "ansible_inventory" {
  description = "Inventory for Ansible running inside WSL"
  value = <<-EOT
[load_balancer]
lb ansible_host=${yandex_compute_instance.node["lb"].network_interface[0].nat_ip_address} private_ip=${yandex_compute_instance.node["lb"].network_interface[0].ip_address}

[frontends]
web1 ansible_host=${yandex_compute_instance.node["web1"].network_interface[0].nat_ip_address} private_ip=${yandex_compute_instance.node["web1"].network_interface[0].ip_address}
web2 ansible_host=${yandex_compute_instance.node["web2"].network_interface[0].nat_ip_address} private_ip=${yandex_compute_instance.node["web2"].network_interface[0].ip_address}
web3 ansible_host=${yandex_compute_instance.node["web3"].network_interface[0].nat_ip_address} private_ip=${yandex_compute_instance.node["web3"].network_interface[0].ip_address}

[all:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new'
EOT
}
