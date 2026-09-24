variable "zone" {
  description = "Зона доступности Yandex Cloud"
  type        = string
  default     = "ru-central1-d"
}

variable "subnet_cidr" {
  description = "CIDR учебной подсети"
  type        = list(string)
  default     = ["10.30.0.0/24"]
}

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_cidr" {
  description = "Внешний IP-адрес, с которого разрешён SSH"
  type        = string
}

variable "vm_name" {
  description = "Имя виртуальной машины"
  type        = string
  default     = "otus-terraform-web-1"
}
