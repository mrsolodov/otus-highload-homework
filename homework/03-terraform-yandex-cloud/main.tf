data "yandex_compute_image" "ubuntu" {
  family    = "ubuntu-2404-lts-oslogin"
  folder_id = "standard-images"
}

resource "yandex_vpc_network" "otus" {
  name = "otus-terraform-network"
}

resource "yandex_vpc_subnet" "otus" {
  name           = "otus-terraform-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.otus.id
  v4_cidr_blocks = var.subnet_cidr
}

resource "yandex_vpc_security_group" "web" {
  name       = "otus-terraform-web-sg"
  network_id = yandex_vpc_network.otus.id

  ingress {
    protocol       = "TCP"
    description    = "SSH from current public IP"
    port           = 22
    v4_cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    description    = "Outbound access"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_instance" "web" {
  name        = var.vm_name
  hostname    = var.vm_name
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.otus.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.web.id]
  }

  metadata = {
    enable-oslogin     = "false"
    serial-port-enable = "0"
    ssh-keys           = "ubuntu:${file(pathexpand(var.ssh_public_key_path))}"

    user-data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      vm_name = var.vm_name
    })
  }
}
