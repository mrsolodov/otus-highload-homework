# Proxmox: две виртуальные машины через Terraform

В этом задании Terraform загружает облачный образ Ubuntu 24.04 в Proxmox и создаёт из него две ВМ: `otus-pve-app1` и `otus-pve-app2`. У каждой по 2 vCPU, 2 ГБ памяти и диску 10 ГБ. Cloud-init настраивает сеть и вход по SSH-ключу.

## Запуск

Нужны Proxmox VE с хранилищами `local` и `local-lvm`, мостом `vmbr0`, два свободных VM ID (по умолчанию 9101 и 9102) и Terraform 1.7+. Перед запуском задайте переменные окружения `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`, `TF_VAR_node_name` и `TF_VAR_ssh_public_key` (содержимое публичного ключа, а не путь к нему). Токену нужны права на создание ВМ и загрузку образа в хранилище. Для стенда с самоподписанным сертификатом можно задать `PROXMOX_VE_INSECURE=true`.

Из каталога `homework/19-proxmox`:

```powershell
terraform init
terraform plan
terraform apply
terraform output virtual_machines
```

По умолчанию ВМ ждут адрес от DHCP. Для моего локального стенда я указал статические адреса в `terraform.tfvars`:

```hcl
vms = {
  app1 = { vm_id = 9101, ipv4_address = "172.28.19.10/24", gateway = "172.28.19.1" }
  app2 = { vm_id = 9102, ipv4_address = "172.28.19.11/24", gateway = "172.28.19.1" }
}
```

`terraform.tfvars` и файл состояния не попадают в Git. Вывод Terraform показывает заданные адреса; фактический IP он не считывает, потому что guest agent выключен. Чтобы убрать ВМ и загруженный образ, выполните `terraform destroy` в том же каталоге.

## На чём проверял

Proxmox 9.2 запустил локально в Hyper-V. Сначала установил его в ВМ VirtualBox, созданной через `prepare-local-lab.ps1`, но VirtualBox на этом компьютере не передал AMD-V гостевой системе. Перенёс диск в Hyper-V; этот путь собран в `prepare-hyperv-lab.ps1`. Защиту VBS в Windows отключать не пришлось.

После переноса поменял в Proxmox сетевой интерфейс `nic0` на `eth0`, адрес узла на `172.28.19.2/24` и шлюз на `172.28.19.1`. Внутри Proxmox появился `/dev/kvm`. `terraform apply` создал обе ВМ, а вход по SSH-ключу на `172.28.19.10` и `172.28.19.11` прошёл. Конфигурация также прошла `terraform validate` и `terraform test`.
