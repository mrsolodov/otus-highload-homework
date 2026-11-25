variable "cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
}

variable "folder_id" {
  description = "Папка для учебного стенда"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_cidr" {
  description = "Внешний IPv4/32 для SSH к учебным ВМ"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr)) && endswith(var.ssh_allowed_cidr, "/32")
    error_message = "Укажите один публичный IPv4-адрес в формате x.x.x.x/32."
  }
}
