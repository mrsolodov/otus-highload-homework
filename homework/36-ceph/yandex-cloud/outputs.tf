output "public_ips" {
  description = "SSH addresses of all three nodes"
  value = {
    for name, vm in yandex_compute_instance.ceph :
    name => vm.network_interface[0].nat_ip_address
  }
}

output "private_ips" {
  description = "Addresses for Ceph public network"
  value = {
    for name, vm in yandex_compute_instance.ceph :
    name => vm.network_interface[0].ip_address
  }
}

output "zones" {
  description = "Independent failure domains for the lab"
  value = {
    for name, vm in yandex_compute_instance.ceph :
    name => vm.zone
  }
}
