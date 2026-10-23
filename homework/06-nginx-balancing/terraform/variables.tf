variable "ssh_allowed_cidr" {
  description = "Public IPv4 CIDR allowed to connect over SSH"
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "Use an IPv4 CIDR such as the current public IP with /32."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key on the machine running Terraform"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "image_family" {
  description = "Ubuntu 24.04 LTS image family"
  type        = string
  default     = "ubuntu-2404-lts-oslogin"
}
