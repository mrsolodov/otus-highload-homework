mock_provider "proxmox" {}

run "two_ubuntu_vms" {
  command = plan

  variables {
    node_name      = "pve"
    ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE8GW6YhHqdNVB7nFeUFA1fFffU+K2dSgXKtYqqybgxD terraform-test"
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.ubuntu) == 2
    error_message = "The plan must contain two VMs."
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.ubuntu["app1"].vm_id == 9101 &&
      proxmox_virtual_environment_vm.ubuntu["app2"].vm_id == 9102
    )
    error_message = "The default VM IDs changed unexpectedly."
  }

  assert {
    condition     = proxmox_virtual_environment_download_file.ubuntu.content_type == "import"
    error_message = "The image must use API-supported import storage."
  }
}
