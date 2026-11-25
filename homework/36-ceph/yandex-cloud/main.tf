data "yandex_compute_image" "ubuntu" {
  family    = "ubuntu-2404-lts-oslogin"
  folder_id = "standard-images"
}

locals {
  nodes = {
    ceph1 = { zone = "ru-central1-a", cidr = "10.136.1.0/24", ip = "10.136.1.11" }
    ceph2 = { zone = "ru-central1-d", cidr = "10.136.2.0/24", ip = "10.136.2.12" }
    ceph3 = { zone = "ru-central1-e", cidr = "10.136.3.0/24", ip = "10.136.3.13" }
  }
}

resource "yandex_vpc_network" "ceph" {
  name = "otus-ceph-network"
}

resource "yandex_vpc_subnet" "ceph" {
  for_each       = local.nodes
  name           = "otus-ceph-${each.key}"
  zone           = each.value.zone
  network_id     = yandex_vpc_network.ceph.id
  v4_cidr_blocks = [each.value.cidr]
}

resource "yandex_vpc_security_group" "ceph" {
  name       = "otus-ceph-sg"
  network_id = yandex_vpc_network.ceph.id

  ingress {
    protocol       = "TCP"
    port           = 22
    description    = "SSH from the owner's public IP"
    v4_cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    protocol       = "ANY"
    description    = "Ceph and cephadm inside the lab network"
    v4_cidr_blocks = ["10.136.0.0/16"]
  }

  egress {
    protocol       = "ANY"
    description    = "Package and container downloads"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_disk" "osd" {
  for_each = local.nodes
  name     = "otus-${each.key}-osd"
  zone     = each.value.zone
  type     = "network-ssd"
  size     = 10

  labels = {
    project  = "otus-highload"
    homework = "ceph"
  }
}

resource "yandex_compute_instance" "ceph" {
  for_each = local.nodes

  name        = "otus-${each.key}"
  hostname    = each.key
  platform_id = "standard-v3"
  zone        = each.value.zone

  resources {
    cores         = 2
    memory        = 16
    core_fraction = 100
  }

  boot_disk {
    auto_delete = true

    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
      type     = "network-hdd"
    }
  }

  secondary_disk {
    disk_id     = yandex_compute_disk.osd[each.key].id
    device_name = "ceph-osd"
    mode        = "READ_WRITE"
    auto_delete = false
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.ceph[each.key].id
    ip_address         = each.value.ip
    nat                = true
    security_group_ids = [yandex_vpc_security_group.ceph.id]
  }

  metadata = {
    enable-oslogin     = "false"
    serial-port-enable = "0"
    ssh-keys           = "ubuntu:${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
    user-data          = file("${path.module}/cloud-init.yaml")
  }

  labels = {
    project  = "otus-highload"
    homework = "ceph"
    role     = "ceph-node"
  }
}
