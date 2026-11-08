terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.120.0"
    }
  }
}

# The provider reads PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN from the environment.
provider "proxmox" {}
