# Облачный вариант стенда (подготовлен, но не запускался)

Terraform создаёт четыре ВМ в Yandex Cloud: `lb`, `web1`, `web2`, `web3`. На трёх фронтендах должны работать Nginx, статическая страница и небольшой Python-бэкенд под uWSGI. Балансировщик направляет запросы на приватные IP фронтендов. Этот вариант не запускался из-за отклонённой заявки на увеличение квот vCPU.

Работающий локальный вариант описан в [README.md](README.md) и [LOCAL-LAB.md](LOCAL-LAB.md). Ниже оставлены команды для облачного варианта на случай, если квоты станут доступны.

В задании указаны четыре ВМ и два фронтенда. Здесь третий фронтенд добавлен как резервный участник пула: все четыре ВМ выполняют полезную функцию, а отказ одного фронтенда оставляет приложение доступным. Бонусный вариант с общей БД не реализован.

| ВМ | Зона | Внутренний IP | Назначение |
| --- | --- | --- | --- |
| lb | ru-central1-d | 10.60.1.10 | Публичный Nginx-балансировщик |
| web1 | ru-central1-d | 10.60.1.11 | Nginx + uWSGI |
| web2 | ru-central1-e | 10.60.2.12 | Nginx + uWSGI |
| web3 | ru-central1-e | 10.60.2.13 | Nginx + uWSGI |

У каждой ВМ — 2 vCPU (20%), 2 ГБ RAM, сетевой HDD 10 ГБ. На время настройки у каждой есть публичный IP для SSH и установки пакетов; HTTP снаружи открыт только на `lb`. SSH открыт только с текущего адреса, заданного через `ssh_allowed_cidr`. Фронтенды принимают HTTP только из приватной подсети зоны `d`, где расположен балансировщик. После проверки весь стенд удаляется `terraform destroy`.

## Режимы балансировки

- `$lbUrl/rr/` — стандартный round-robin Nginx; адрес `$lbUrl` берётся из Terraform output в разделе «Проверка».
- `$lbUrl/hash/?key=otus` — consistent hash по значению аргумента `key`. Запросы с одинаковым ключом обычно попадают на один узел, пока состав доступных узлов не меняется.
- `/rr/api/health` и `/hash/api/health?key=otus` — ответы Python/uWSGI-приложения с именем обработавшего узла.

Фронтенд добавляет `X-Frontend`, балансировщик — `X-Balancing-Mode`. При ошибке соединения с фронтендом балансировщик повторяет запрос на другом узле. В открытом Nginx проверка доступности здесь пассивная: состояние узла уточняется по реальным запросам, поэтому первый запрос после отказа может пройти через попытку соединения с отказавшим узлом.

## Что нужно перед запуском

- Windows: Terraform и Yandex Cloud CLI, настроенный профиль `yc` и публичный SSH-ключ `~/.ssh/id_ed25519.pub`.
- WSL Ubuntu: Ansible и приватный ключ `~/.ssh/id_ed25519` с правами `0600`.
- Квоты не меньше 4 vCPU в каждой из зон `ru-central1-d` и `ru-central1-e`; 20 ГиБ HDD в каждой зоне. Сам факт одобрения заявки лучше проверить повторным запросом текущих квот.
- Доступные промокоды/баланс в Yandex Cloud. Создание четырёх ВМ, дисков и публичных адресов расходует средства до удаления стенда.

Команды ниже рассчитаны на PowerShell в Windows, если явно не сказано иное. Перейти в каталог Terraform:

```powershell
Set-Location "D:\Projects\otus-highload-homework\homework\06-nginx-balancing\terraform"
```

Обновить IAM-токен сервисного аккаунта в текущем окне PowerShell:

```powershell
$folderId = (yc config get folder-id).Trim()
$serviceAccountId = (
    yc iam service-account get --name terraform-otus --folder-id $folderId --format json |
    ConvertFrom-Json
).id

$env:YC_TOKEN = (yc iam create-token --impersonate-service-account-id $serviceAccountId).Trim()
$env:YC_CLOUD_ID = (yc config get cloud-id).Trim()
$env:YC_FOLDER_ID = $folderId

if ([string]::IsNullOrWhiteSpace($env:YC_TOKEN)) {
    throw "Не удалось получить IAM-токен"
}
```

Записать актуальный публичный IP в локальный `terraform.tfvars` (файл игнорируется Git):

```powershell
$currentIp = (Invoke-RestMethod -Uri "https://api.ipify.org").ToString().Trim()
"ssh_allowed_cidr = `"$currentIp/32`"" |
    Set-Content -Path ".\terraform.tfvars" -Encoding utf8
```

Если IP поменяется, обновить `terraform.tfvars` и повторно применить конфигурацию. Далее проверить конфигурацию:

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
```

Перед `apply` убедиться, что план содержит четыре ВМ в нужных зонах и не удаляет посторонние ресурсы. Затем:

```powershell
terraform apply
```

Создать локальный inventory для WSL без BOM и без потери переводов строк:

```powershell
$inventoryPath = "D:\Projects\otus-highload-homework\homework\06-nginx-balancing\ansible\inventory.ini"
$inventoryLines = @(terraform output -raw ansible_inventory)
[System.IO.File]::WriteAllText(
    $inventoryPath,
    ($inventoryLines -join "`n") + "`n",
    [System.Text.UTF8Encoding]::new($false)
)
```

Проверить SSH и запустить Ansible из WSL:

```powershell
wsl bash -lc "cd /mnt/d/Projects/otus-highload-homework/homework/06-nginx-balancing/ansible && ansible all -i inventory.ini -m ping"
wsl bash -lc "cd /mnt/d/Projects/otus-highload-homework/homework/06-nginx-balancing/ansible && ansible-playbook -i inventory.ini site.yml"
```

Ansible сначала настраивает фронтенды и проверяет их локально, затем настраивает и проверяет балансировщик. Повторный запуск должен быть без изменений, кроме возможного обновления системных пакетов и связанных с ним действий.

## Проверка

Из каталога `terraform` в PowerShell:

```powershell
$lbUrl = (terraform output -raw lb_url).Trim()

1..9 | ForEach-Object {
    $response = Invoke-WebRequest -UseBasicParsing -Uri "$lbUrl/rr/api/health" -TimeoutSec 15
    "round-robin: HTTP $($response.StatusCode), frontend=$($response.Headers['X-Frontend']), body=$($response.Content.Trim())"
}

1..6 | ForEach-Object {
    $response = Invoke-WebRequest -UseBasicParsing -Uri "$lbUrl/hash/api/health?key=otus" -TimeoutSec 15
    "hash: HTTP $($response.StatusCode), frontend=$($response.Headers['X-Frontend']), body=$($response.Content.Trim())"
}
```

В первом наборе запросов ожидается чередование `web1`/`web2`/`web3`; во втором один и тот же `key` должен стабильно попадать на один фронтенд. Затем отдельно проверяются статика и заголовки через `/rr/` и `/hash/?key=otus`.

Для проверки отказа следует остановить Nginx на одном фронтенде, повторить запросы к балансировщику и **обязательно** запустить службу обратно. После восстановления проверить, что все три имени снова появляются при round-robin. Результаты команд, конфигурацию и скриншоты сохранять в `evidence/` после фактического запуска, а не заранее.

## Удаление стенда

Когда результаты сохранены, из каталога `terraform` выполнить:

```powershell
terraform destroy
terraform state list
```

Проверить также отсутствие ВМ и дисков через `yc compute instance list` и `yc compute disk list`. Наличие нуля ресурсов в Terraform state само по себе не доказывает отсутствие облачных ресурсов, если удаление завершилось ошибкой.
