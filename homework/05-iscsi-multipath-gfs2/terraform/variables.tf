variable "zone" {
  description = "Зона размещения gfs1 и gfs3"
  type        = string
  default     = "ru-central1-d"
}

variable "storage_zone" {
  description = "Зона размещения iSCSI target и gfs2"
  type        = string
  default     = "ru-central1-e"
}

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_cidr" {
  description = "Публичный IP, с которого разрешён SSH"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "ssh_allowed_cidr должен быть записан в формате CIDR."
  }
}

variable "cluster_cidr" {
  description = "Общая адресная область лабораторного стенда"
  type        = string
  default     = "10.50.0.0/16"
}

variable "subnet_a_cidr" {
  description = "Первый путь для узлов в ru-central1-d"
  type        = list(string)
  default     = ["10.50.1.0/24"]
}

variable "subnet_b_cidr" {
  description = "Второй путь для узлов в ru-central1-d"
  type        = list(string)
  default     = ["10.50.2.0/24"]
}

variable "storage_subnet_a_cidr" {
  description = "Первый путь для узлов в ru-central1-e"
  type        = list(string)
  default     = ["10.50.11.0/24"]
}

variable "storage_subnet_b_cidr" {
  description = "Второй путь для узлов в ru-central1-e"
  type        = list(string)
  default     = ["10.50.12.0/24"]
}