output "virtual_machines" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.ceph : name => {
      vm_id = vm.vm_id
      ip    = var.vms[name].ip
      name  = vm.name
    }
  }
}
