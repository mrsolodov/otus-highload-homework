output "virtual_machines" {
  description = "VM names, IDs, and requested network settings"
  value = {
    for name, vm in proxmox_virtual_environment_vm.ubuntu : name => {
      vm_id        = vm.vm_id
      name         = vm.name
      node_name    = vm.node_name
      ipv4_address = var.vms[name].ipv4_address
    }
  }
}
