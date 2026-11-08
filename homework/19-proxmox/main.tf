resource "proxmox_download_file" "ubuntu" {
  node_name    = var.node_name
  datastore_id = var.image_datastore_id
  content_type = "import"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "otus-noble-server-cloudimg-amd64.qcow2"
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "ubuntu" {
  for_each = var.vms

  name            = "otus-pve-${each.key}"
  node_name       = var.node_name
  vm_id           = each.value.vm_id
  description     = "OTUS homework 19: managed by Terraform"
  tags            = ["otus", "terraform"]
  started         = true
  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.vm_datastore_id
    import_from  = proxmox_download_file.ubuntu.id
    interface    = "virtio0"
    size         = var.vm_disk_size_gb
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = var.vm_datastore_id

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = each.value.gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [trimspace(var.ssh_public_key)]
    }
  }
}
