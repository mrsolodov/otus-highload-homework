# Домашняя работа по Terraform

В этой работе я развернул небольшую инфраструктуру в Yandex Cloud с помощью Terraform.

Основная задача была в том, чтобы создать виртуальную машину не вручную через консоль, а полностью описать её и связанные ресурсы в коде. После создания на ВМ через cloud-init устанавливается Nginx и создаётся простая тестовая страница.

## Что создаётся

Terraform создаёт:

- отдельную сеть;
- подсеть `10.30.0.0/24` в зоне `ru-central1-d`;
- группу безопасности;
- виртуальную машину с Ubuntu 24.04;
- загрузочный диск на 10 ГБ;
- публичный IP для проверки SSH и Nginx.

Для ВМ выбрал небольшую конфигурацию: 2 ядра, 2 ГБ памяти и `core_fraction = 20`. Для учебного стенда этого достаточно.

В группе безопасности открыты два порта:

- `22` — только для моего текущего публичного IP;
- `80` — для проверки страницы Nginx.

## Файлы

- `versions.tf` — версия Terraform и провайдера Yandex Cloud;
- `variables.tf` — используемые переменные;
- `main.tf` — сеть, подсеть, группа безопасности и ВМ;
- `outputs.tf` — IP-адреса и команды для проверки;
- `cloud-init.yaml.tftpl` — установка Nginx и создание тестовой страницы;
- `evidence` — результаты проверок после развёртывания.

Файл `terraform.tfvars`, Terraform state и каталог `.terraform` в репозиторий не добавляются.

## Подготовка

На компьютере должны быть установлены Terraform и Yandex Cloud CLI. Также должен быть настроен профиль `yc`.

Для запуска от имени сервисного аккаунта я использовал временный IAM-токен:

```powershell
$folderId = (yc config get folder-id).Trim()

$serviceAccountId = (
    yc iam service-account get `
        --name terraform-otus `
        --folder-id $folderId `
        --format json |
    ConvertFrom-Json
).id

$env:YC_TOKEN = (
    yc iam create-token `
        --impersonate-service-account-id $serviceAccountId
).Trim()

$env:YC_CLOUD_ID = (yc config get cloud-id).Trim()
$env:YC_FOLDER_ID = $folderId
```

Токен сохраняется только в переменной текущей сессии PowerShell.

## Настройка SSH-доступа

Чтобы не открывать SSH для всего интернета, текущий публичный IP записывается в локальный `terraform.tfvars`:

```powershell
$currentIp = (
    Invoke-RestMethod -Uri "https://api.ipify.org"
).ToString().Trim()

@"
ssh_allowed_cidr = "$currentIp/32"
"@ | Set-Content `
    -Path ".\terraform.tfvars" `
    -Encoding utf8
```

Если внешний IP изменился, этот файл нужно создать заново и повторить `terraform apply`.

## Запуск

```powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

После выполнения `apply` Terraform выводит публичный IP ВМ, внутренний IP, адрес страницы и команду для подключения по SSH.

## Проверка

Сначала проверил страницу Nginx с локального компьютера. Сервер вернул HTTP-код `200`.

Потом подключился к ВМ по SSH и проверил состояние cloud-init и Nginx:

```powershell
$publicIp = terraform output -raw vm_public_ip
$keyPath = Join-Path $env:USERPROFILE ".ssh\id_ed25519"

ssh `
    -i $keyPath `
    -o IdentitiesOnly=yes `
    ubuntu@$publicIp `
    "cloud-init status; systemctl is-active nginx; curl -fsS http://localhost/"
```

Результат проверки:

```text
status: done
active
```

Повторный `terraform plan` после создания ресурсов показал:

```text
No changes. Your infrastructure matches the configuration.
```

Выводы команд и HTML тестовой страницы сохранил в каталоге `evidence`.

## Удаление стенда

После проверки удалил созданные ресурсы, чтобы они не продолжали расходовать средства:

```powershell
terraform destroy
```

После удаления `terraform state list` не содержит ресурсов, а ВМ отсутствует в Yandex Cloud.
