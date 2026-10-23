data "yandex_compute_image" "ubuntu" {
  family    = var.image_family
  folder_id = "standard-images"
}

locals {
  instances = {
    lb   = { zone = "ru-central1-d", address = "10.60.1.10", role = "lb" }
    web1 = { zone = "ru-central1-d", address = "10.60.1.11", role = "web" }
    web2 = { zone = "ru-central1-e", address = "10.60.2.12", role = "web" }
    web3 = { zone = "ru-central1-e", address = "10.60.2.13", role = "web" }
  }
}

resource "yandex_vpc_network" "otus" {
  name = "otus-nginx-network"
}

resource "yandex_vpc_subnet" "zone" {
  for_each = {
    "ru-central1-d" = "10.60.1.0/24"
    "ru-central1-e" = "10.60.2.0/24"
  }

  name           = "otus-nginx-${each.key}"
  zone           = each.key
  network_id     = yandex_vpc_network.otus.id
  v4_cidr_blocks = [each.value]
}

resource "yandex_vpc_security_group" "lb" {
  name       = "otus-nginx-lb-sg"
  network_id = yandex_vpc_network.otus.id

  ingress {
    protocol       = "TCP"
    description    = "SSH from the current public IP"
    port           = 22
    v4_cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    protocol       = "TCP"
    description    = "Public HTTP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    description    = "Outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "web" {
  name       = "otus-nginx-web-sg"
  network_id = yandex_vpc_network.otus.id

  ingress {
    protocol       = "TCP"
    description    = "SSH from the current public IP"
    port           = 22
    v4_cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTP from the load balancer private subnet"
    port           = 80
    v4_cidr_blocks = ["10.60.1.0/24"]
  }

  egress {
    protocol       = "ANY"
    description    = "Outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_instance" "node" {
  for_each = local.instances

  name        = "otus-nginx-${each.key}"
  hostname    = each.key
  platform_id = "standard-v3"
  zone        = each.value.zone

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
    subnet_id = yandex_vpc_subnet.zone[each.value.zone].id
    ip_address = each.value.address
    nat        = true
    security_group_ids = [
      each.value.role == "lb" ? yandex_vpc_security_group.lb.id : yandex_vpc_security_group.web.id
    ]
  }

  metadata = {
    enable-oslogin     = "false"
    serial-port-enable = "0"
    ssh-keys           = "ubuntu:${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
  }

  labels = {
    project  = "otus-highload"
    homework = "nginx-balancing"
    role     = each.value.role
  }
}
