variable "node_name" {
  type        = string
  description = "Existing Proxmox node name"
}

variable "ssh_public_key" {
  type        = string
  description = "Contents of the SSH public key for ubuntu"

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+) [A-Za-z0-9+/=]+", trimspace(var.ssh_public_key)))
    error_message = "Provide an OpenSSH public key, not a path."
  }
}

variable "image_datastore_id" {
  type    = string
  default = "local"
}

variable "vm_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "gateway" {
  type    = string
  default = "172.28.19.1"
}

variable "system_disk_gb" {
  type    = number
  default = 20
  validation {
    condition     = var.system_disk_gb >= 20
    error_message = "The system disk must be at least 20 GiB."
  }
}

variable "osd_disk_gb" {
  type    = number
  default = 20
  validation {
    condition     = var.osd_disk_gb >= 10
    error_message = "The OSD disk must be at least 10 GiB."
  }
}

variable "memory_mb" {
  type    = number
  default = 4096
  validation {
    condition     = var.memory_mb >= 4096
    error_message = "Each lab VM needs at least 4096 MiB."
  }
}

variable "vms" {
  type = map(object({
    vm_id = number
    ip    = string
  }))
  default = {
    ceph1 = { vm_id = 9136, ip = "172.28.19.36/24" }
    ceph2 = { vm_id = 9137, ip = "172.28.19.37/24" }
    ceph3 = { vm_id = 9138, ip = "172.28.19.38/24" }
  }

  validation {
    condition = length(var.vms) == 3 && length(distinct([for vm in values(var.vms) : vm.vm_id])) == 3 && alltrue([
      for name, vm in var.vms :
      can(regex("^[a-z][a-z0-9-]*$", name)) &&
      vm.vm_id >= 100 && vm.vm_id == floor(vm.vm_id) &&
      can(cidrnetmask(vm.ip))
    ])
    error_message = "Provide three hosts with distinct VM IDs and valid CIDR addresses."
  }
}
