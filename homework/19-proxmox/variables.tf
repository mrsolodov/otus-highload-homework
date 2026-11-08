variable "node_name" {
  description = "Proxmox VE node where the VMs and image will be created"
  type        = string

  validation {
    condition     = length(trimspace(var.node_name)) > 0
    error_message = "node_name must not be empty."
  }
}

variable "image_datastore_id" {
  description = "Storage that supports the import content type (normally local)"
  type        = string
  default     = "local"
}

variable "vm_datastore_id" {
  description = "Storage for VM disks and cloud-init disks (normally local-lvm)"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Existing Proxmox Linux bridge attached to the VM network"
  type        = string
  default     = "vmbr0"
}

variable "ssh_public_key" {
  description = "OpenSSH public key used by the ubuntu user"
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+) [A-Za-z0-9+/=]+", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be an OpenSSH public key."
  }
}

variable "vms" {
  description = "Two test VMs; choose free VM IDs in your Proxmox cluster"
  type = map(object({
    vm_id        = number
    ipv4_address = optional(string, "dhcp")
    gateway      = optional(string)
  }))

  default = {
    app1 = { vm_id = 9101 }
    app2 = { vm_id = 9102 }
  }

  validation {
    condition = length(var.vms) == 2 && alltrue([
      for name, vm in var.vms :
      can(regex("^[a-z][a-z0-9-]*$", name)) &&
      vm.vm_id >= 100 && vm.vm_id <= 999999999 && vm.vm_id == floor(vm.vm_id) &&
      (vm.ipv4_address == "dhcp" ? vm.gateway == null : can(cidrnetmask(vm.ipv4_address)))
    ]) && length(distinct([for vm in values(var.vms) : vm.vm_id])) == length(var.vms)
    error_message = "Provide two VMs with distinct valid IDs, DNS-safe names, and DHCP or a CIDR address."
  }
}
