output "vm_public_ip" {
  description = "Публичный IPv4-адрес виртуальной машины"
  value       = yandex_compute_instance.web.network_interface[0].nat_ip_address
}

output "vm_private_ip" {
  description = "Внутренний IPv4-адрес виртуальной машины"
  value       = yandex_compute_instance.web.network_interface[0].ip_address
}

output "ssh_command" {
  description = "Команда подключения по SSH"
  value       = "ssh ubuntu@${yandex_compute_instance.web.network_interface[0].nat_ip_address}"
}

output "http_url" {
  description = "Адрес тестовой страницы Nginx"
  value       = "http://${yandex_compute_instance.web.network_interface[0].nat_ip_address}/"
}
