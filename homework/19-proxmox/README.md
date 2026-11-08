# Домашняя работа 19: виртуализация в Proxmox

В работе описал через Terraform две небольшие виртуальные машины Ubuntu 24.04 в Proxmox VE. Образ загружается в хранилище Proxmox, после чего из него создаются `otus-pve-app1` и `otus-pve-app2`. Доступ по SSH настраивается через cloud-init.

## Что нужно для запуска

- Proxmox VE с узлом, на котором есть хранилище `local` с типом содержимого `Import`, `local-lvm` для дисков и мост `vmbr0`. Если имена другие, их можно передать через переменные Terraform.
- Два свободных VM ID: по умолчанию 9101 и 9102. На диски потребуется примерно 40 ГБ, плюс место под скачанный образ.
- Рабочий DHCP в сети моста или собственные статические адреса для двух ВМ.
- Terraform 1.7+ и API-токен Proxmox с правами создавать ВМ, загружать образ, использовать выбранные хранилища и сеть. Для загрузки через `download-url` нужны `Datastore.AllocateTemplate`, `Sys.Audit` и `Sys.Modify`. Токен не надо записывать в файлы проекта.
- Публичный SSH-ключ `~/.ssh/id_ed25519.pub` на компьютере, с которого выполняется `terraform apply`.

Код использует провайдер `bpg/proxmox` версии 0.120.0. Его настройки API берутся из переменных окружения. TLS-сертификат сервера должен быть доверенным; если используется самоподписанный сертификат учебного стенда, проверку можно отдельно отключить переменной `PROXMOX_VE_INSECURE=true`.

## Запуск из PowerShell

```powershell
Set-Location "homework/19-proxmox"
$env:PROXMOX_VE_ENDPOINT = Read-Host "Адрес API Proxmox (HTTPS и порт 8006)"
$secret = Read-Host "API-токен Proxmox" -AsSecureString
$tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try {
    $env:PROXMOX_VE_API_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr)
}
$env:TF_VAR_node_name = Read-Host "Имя узла Proxmox"
$env:TF_VAR_ssh_public_key = (Get-Content (Join-Path $env:USERPROFILE '.ssh/id_ed25519.pub') -Raw).Trim()

terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
terraform output virtual_machines
```

Формат API-токена: `пользователь@realm!имя_токена=значение`. Если у вас другая сеть, хранилища или заняты ID, измените переменные `network_bridge`, `image_datastore_id`, `vm_datastore_id` и `vms` локальным файлом `terraform.tfvars` до `plan`. У двух ВМ по 2 vCPU, 2 ГБ RAM и диску 20 ГБ. При DHCP адреса удобно узнать из DHCP-сервера; guest agent в этой конфигурации выключен, поэтому Terraform выводит запрошенные сетевые настройки, а не обнаруженный гостевой IP.

Пример статических адресов записывается в `terraform.tfvars` с ключами `app1` и `app2` и полями `vm_id`, `ipv4_address` (в виде CIDR) и `gateway`. Адреса и шлюз должны подходить вашей сети; готовых IP для чужого стенда в репозитории нет.

После проверки удалить стенд можно командой `terraform destroy` из этой же папки. Затем завершите сессию PowerShell, чтобы убрать API-токен из окружения. Файлы `.terraform`, `terraform.tfstate` и `terraform.tfvars` игнорируются Git.

## Что проверено

GitHub Actions проверяет форматирование, `terraform validate` и план двух ВМ с подменённым провайдером в `terraform test`. Эта проверка не подключается к Proxmox. Реальный `apply`, загрузку образа и доступность созданных ВМ нужно проверить на доступном стенде; результатов такого запуска здесь нет.
