data "yandex_compute_image" "ubuntu" {
  family    = "ubuntu-2404-lts-oslogin"
  folder_id = "standard-images"
}

locals {
  gfs_nodes = {
    gfs1 = {
      zone                = var.zone
      ip_a                = "10.50.1.21"
      ip_b                = "10.50.2.21"
      use_storage_subnets = false
    }

    gfs2 = {
      zone                = var.storage_zone
      ip_a                = "10.50.11.22"
      ip_b                = "10.50.12.22"
      use_storage_subnets = true
    }

    gfs3 = {
      zone                = var.zone
      ip_a                = "10.50.1.23"
      ip_b                = "10.50.2.23"
      use_storage_subnets = false
    }
  }
}

resource "yandex_vpc_network" "gfs2" {
  name = "otus-gfs2-network"
}

resource "yandex_vpc_subnet" "path_a" {
  name           = "otus-gfs2-path-a"
  zone           = var.zone
  network_id     = yandex_vpc_network.gfs2.id
  v4_cidr_blocks = var.subnet_a_cidr
}

resource "yandex_vpc_subnet" "path_b" {
  name           = "otus-gfs2-path-b"
  zone           = var.zone
  network_id     = yandex_vpc_network.gfs2.id
  v4_cidr_blocks = var.subnet_b_cidr
}

resource "yandex_vpc_subnet" "storage_path_a" {
  name           = "otus-gfs2-storage-path-a"
  zone           = var.storage_zone
  network_id     = yandex_vpc_network.gfs2.id
  v4_cidr_blocks = var.storage_subnet_a_cidr
}

resource "yandex_vpc_subnet" "storage_path_b" {
  name           = "otus-gfs2-storage-path-b"
  zone           = var.storage_zone
  network_id     = yandex_vpc_network.gfs2.id
  v4_cidr_blocks = var.storage_subnet_b_cidr
}

resource "yandex_vpc_security_group" "gfs2" {
  name        = "otus-gfs2-sg"
  description = "Security group for the OTUS iSCSI and GFS2 laboratory"
  network_id  = yandex_vpc_network.gfs2.id

  ingress {
    protocol       = "TCP"
    description    = "SSH from current public IP"
    port           = 22
    v4_cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    protocol       = "ANY"
    description    = "Internal cluster and iSCSI traffic"
    v4_cidr_blocks = [var.cluster_cidr]
  }

  egress {
    protocol       = "ANY"
    description    = "Outbound access"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_disk" "gfs_lun" {
  name = "otus-gfs2-lun"
  type = "network-ssd"
  zone = var.storage_zone
  size = 10

  labels = {
    project  = "otus-highload"
    homework = "gfs2"
  }
}

resource "yandex_compute_instance" "iscsi_target" {
  name                      = "gfs-target"
  hostname                  = "gfs-target"
  platform_id               = "standard-v3"
  zone                      = var.storage_zone
  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    auto_delete = true

    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
      type     = "network-hdd"
    }
  }

  secondary_disk {
    disk_id     = yandex_compute_disk.gfs_lun.id
    device_name = "gfs-lun"
    mode        = "READ_WRITE"
    auto_delete = false
  }

  network_interface {
    index              = 0
    subnet_id          = yandex_vpc_subnet.storage_path_a.id
    ip_address         = "10.50.11.10"
    nat                = true
    security_group_ids = [yandex_vpc_security_group.gfs2.id]
  }

  network_interface {
    index              = 1
    subnet_id          = yandex_vpc_subnet.storage_path_b.id
    ip_address         = "10.50.12.10"
    nat                = false
    security_group_ids = [yandex_vpc_security_group.gfs2.id]
  }

  metadata = {
    enable-oslogin     = "false"
    serial-port-enable = "0"
    ssh-keys           = "ubuntu:${file(pathexpand(var.ssh_public_key_path))}"
    user-data          = file("${path.module}/cloud-init.yaml")
  }

  labels = {
    project  = "otus-highload"
    homework = "gfs2"
    role     = "iscsi-target"
  }
}

resource "yandex_compute_instance" "gfs_node" {
  for_each = local.gfs_nodes

  name                      = each.key
  hostname                  = each.key
  platform_id               = "standard-v3"
  zone                      = each.value.zone
  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    auto_delete = true

    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
      type     = "network-hdd"
    }
  }

  network_interface {
    index = 0

    subnet_id = (
      each.value.use_storage_subnets
      ? yandex_vpc_subnet.storage_path_a.id
      : yandex_vpc_subnet.path_a.id
    )

    ip_address         = each.value.ip_a
    nat                = true
    security_group_ids = [yandex_vpc_security_group.gfs2.id]
  }

  network_interface {
    index = 1

    subnet_id = (
      each.value.use_storage_subnets
      ? yandex_vpc_subnet.storage_path_b.id
      : yandex_vpc_subnet.path_b.id
    )

    ip_address         = each.value.ip_b
    nat                = false
    security_group_ids = [yandex_vpc_security_group.gfs2.id]
  }

  metadata = {
    enable-oslogin     = "false"
    serial-port-enable = "0"
    ssh-keys           = "ubuntu:${file(pathexpand(var.ssh_public_key_path))}"
    user-data          = file("${path.module}/cloud-init.yaml")
  }

  labels = {
    project  = "otus-highload"
    homework = "gfs2"
    role     = "gfs2-node"
  }
}