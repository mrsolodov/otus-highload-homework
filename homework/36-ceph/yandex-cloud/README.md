# CephFS на трёх ВМ Yandex Cloud

Это облачный вариант [задания 36](../README.md). Он рассчитан на короткий эксперимент, после которого все созданные ресурсы удаляются. На 25.11.2026 кластер был развёрнут и испытан; [замеры и проверка отказа](../evidence/yandex-cloud-2026-11-25.md) сохранены, все 11 ресурсов удалены.

| Нода | Зона | Частный IP | VM | Диски |
| --- | --- | --- | --- | --- |
| ceph1 | ru-central1-a | 10.136.1.11 | 2 vCPU, 16 ГиБ | 20 ГиБ HDD ОС + 10 ГиБ SSD OSD |
| ceph2 | ru-central1-d | 10.136.2.12 | 2 vCPU, 16 ГиБ | 20 ГиБ HDD ОС + 10 ГиБ SSD OSD |
| ceph3 | ru-central1-e | 10.136.3.13 | 2 vCPU, 16 ГиБ | 20 ГиБ HDD ОС + 10 ГиБ SSD OSD |

Используются отдельная VPC, три подсети, одна группа безопасности и три динамических публичных IP. Внутренний трафик между нодами разрешён в `10.136.0.0/16`; SSH открыт только с адреса `ssh_allowed_cidr`. Публичные IP нужны для установки пакетов и контейнеров на каждой ВМ. Публичные IP могут измениться после перезапуска; частные IP остаются фиксированными. После `yc compute instance start` заново получайте адреса через `yc compute instance list` или `terraform refresh` и `terraform output public_ips`.

Обнаруженные квоты облака позволяют ровно одну такую ВМ и один OSD-диск в каждой из указанных зон. 10 ГиБ удовлетворяют техническому минимуму `cephadm` для OSD (5 ГиБ), но Ceph не рекомендует столь маленькие диски для реальной нагрузки. Бенчмарк даёт только характеристику этого стенда.

На 25.11.2026 в гранте было 486 ₽ до 22.09.2027. По [тарифному примеру Compute Cloud](https://yandex.cloud/ru/docs/compute/pricing) вычислительная часть составляет около 23,28 ₽/ч за три ВМ; [диски](https://yandex.cloud/ru/docs/compute/pricing) и [публичные IP](https://yandex.cloud/ru/docs/vpc/pricing) оплачиваются дополнительно. Диски оплачиваются даже после остановки ВМ. Проверяйте баланс и удаляйте стенд через `terraform destroy` после опыта.

## 1. Подготовить Terraform

Команды в PowerShell из этого каталога. В Happ направьте напрямую `yc.exe`, `terraform.exe`, `ssh.exe`, `curl.exe` и установленный `terraform-provider-yandex_v0.238.0.exe`. Terraform запускает провайдер отдельным процессом; если направить напрямую только `terraform.exe`, провайдер может не подключиться к API. Проверить текущую папку и существующий сервисный аккаунт:

```powershell
yc config get cloud-id
yc config get folder-id
yc iam service-account get --name terraform-otus
```

Выпустить временный токен в текущую сессию, задать параметры и выяснить внешний IP этой сессии:

```powershell
$ErrorActionPreference = 'Stop'
$serviceAccountId = (yc iam service-account get --name terraform-otus --format json | ConvertFrom-Json).id
$env:YC_TOKEN = (yc iam create-token --impersonate-service-account-id $serviceAccountId).Trim()
$env:TF_VAR_cloud_id = (yc config get cloud-id).Trim()
$env:TF_VAR_folder_id = (yc config get folder-id).Trim()
$myIp = (& curl.exe --silent --show-error --noproxy '*' 'https://api.ipify.org').Trim()
$env:TF_VAR_ssh_allowed_cidr = "$myIp/32"
Write-Host "SSH разрешён с $env:TF_VAR_ssh_allowed_cidr"
```

`curl.exe` должен идти тем же прямым маршрутом, что и `ssh.exe`. В нашем запуске `Invoke-RestMethod` через PowerShell показал адрес VPN, который отличался от адреса SSH. Фактический IP можно проверить после входа командой `echo "$SSH_CONNECTION"` на ВМ; затем ограничить правило группы безопасности этим IP `/32`. Токен и приватный ключ не записывайте в файлы репозитория.

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan '-out=ceph.tfplan'
terraform show ceph.tfplan
terraform apply ceph.tfplan
terraform output public_ips
terraform output private_ips
```

Если `terraform init` не видит Terraform Registry из-за маршрута Happ, скачайте зафиксированный провайдер 0.238.0 с [официального релиза Yandex Cloud](https://github.com/yandex-cloud/terraform-provider-yandex/releases/tag/v0.238.0) в локальное зеркало, проверьте SHA256 и повторите инициализацию:

```powershell
$mirror = '.terraform/provider-mirror/registry.terraform.io/yandex-cloud/yandex'
New-Item -ItemType Directory -Path $mirror -Force | Out-Null
$zip = Join-Path $mirror 'terraform-provider-yandex_0.238.0_windows_amd64.zip'
Invoke-WebRequest 'https://github.com/yandex-cloud/terraform-provider-yandex/releases/download/v0.238.0/terraform-provider-yandex_0.238.0_windows_amd64.zip' -OutFile $zip
if ((Get-FileHash -Algorithm SHA256 $zip).Hash -ne '22EC73A427061AFFF59F4E156856541C92001CD815882C9413788004CA7196B6') { throw 'Неверный SHA256 провайдера' }
terraform init -input=false -lockfile=readonly '-plugin-dir=.terraform/provider-mirror'
Get-ChildItem .terraform/providers -Recurse -Filter 'terraform-provider-yandex*.exe' | Select-Object -ExpandProperty FullName
```

Полученный путь к `.exe` добавьте в Happ с прямым подключением. Зеркало лежит внутри `.terraform` и не попадает в Git.

План должен создавать только три ВМ, три OSD-диска, VPC, три подсети и группу безопасности. Загрузочные диски удаляются вместе с ВМ; отдельные OSD-диски управляются Terraform и должны исчезнуть после `destroy`. Проверяйте, что текущая папка `yc` — именно учебная `otus-highload`.

## 2. Подготовить Ubuntu

Из `terraform output public_ips` возьмите адреса, подключайтесь как `ubuntu` своим ключом. На **каждой** из трёх нод:

```bash
hostname
getent hosts ceph1 ceph2 ceph3
sudo apt-get update
sudo apt-get install -y docker.io lvm2 chrony openssh-server cephadm
sudo systemctl enable --now docker chrony ssh
sudo cephadm check-host
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
```

В `lsblk` проверьте, какой диск имеет размер 10 ГиБ и не содержит разделов или файловой системы. На Ubuntu это часто `/dev/vdb`, но для OSD используйте только путь, подтверждённый на данной ноде. Docker и Chrony должны работать. При ошибке загрузки пакетов проверьте выход в интернет с ВМ.

## 3. Развернуть Ceph

На **ceph1**:

```bash
sudo cephadm add-repo --release tentacle
sudo cephadm install
printf '[global]\npublic network = 10.136.0.0/16\n' | sudo tee /tmp/ceph-initial.conf
sudo cephadm bootstrap --mon-ip 10.136.1.11 --config /tmp/ceph-initial.conf --skip-mon-network --ssh-user ubuntu --skip-dashboard --skip-monitoring-stack
sudo cephadm install ceph-common
sudo ceph config get mon public_network
sudo ceph -s
sudo ceph config set mgr mgr/cephadm/autotune_memory_target_ratio 0.3
sudo ceph config set mds mds_cache_memory_limit 1073741824
```

Скопируйте публичный ключ cephadm в `authorized_keys` пользователя `ubuntu` на ceph2 и ceph3. С Windows (подставьте реальные публичные IP из вывода Terraform). Если прямой SSH к публичному IP ceph3 недоступен, подключайтесь через ceph2: `ssh -J ubuntu@<ceph2-public-ip> ubuntu@10.136.3.13`.

```powershell
$ips = terraform output -json public_ips | ConvertFrom-Json
$key = "$HOME\.ssh\id_ed25519"
$cephPub = (& ssh.exe -i $key "ubuntu@$($ips.ceph1)" 'cat /etc/ceph/ceph.pub').Trim()
if ($LASTEXITCODE -ne 0 -or -not $cephPub.StartsWith('ssh-')) { throw 'Не удалось прочитать ключ cephadm' }
foreach ($name in @('ceph2', 'ceph3')) {
    $cephPub | & ssh.exe -i $key "ubuntu@$($ips.$name)" 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
    if ($LASTEXITCODE -ne 0) { throw "Не удалось установить ключ на $name" }
}
```

На **ceph1**:

```bash
sudo ceph orch host add ceph2 10.136.2.12
sudo ceph orch host add ceph3 10.136.3.13
sudo ceph orch apply mon --placement='3 ceph1 ceph2 ceph3'
sudo ceph orch apply mgr --placement='2 ceph1 ceph2'
sudo ceph orch device ls --wide --refresh
```

Дождитесь трёх MON и quorum 3/3. Если первое применение вернёт `Unknown hosts`, дождитесь появления всех трёх хостов в `ceph orch host ls` и повторите обе команды `ceph orch apply`; в испытании это устранило ошибку регистрации. После проверки пути каждого 10-ГиБ диска добавьте по одному OSD на ноду. Следующий пример допустим **только если** на всех трёх нодах OSD-диск — `/dev/vdb`:

```bash
sudo ceph orch daemon add osd ceph1:/dev/vdb
sudo ceph orch daemon add osd ceph2:/dev/vdb
sudo ceph orch daemon add osd ceph3:/dev/vdb
sudo ceph osd tree
sudo ceph -s
```

`daemon add osd` перезаписывает указанный диск. При ошибках или если `/dev/vdb` является загрузочным диском остановитесь и перепроверьте `lsblk` и `ceph orch device ls`.

## 4. CephFS, клиент и испытания

После `3 up, 3 in` на ceph1 создайте ФС и два MDS:

```bash
sudo ceph fs volume create cephfs
sudo ceph orch apply mds cephfs --placement='2 ceph2 ceph3'
sudo ceph fs status cephfs
sudo ceph osd pool ls detail
```

Дождитесь активного MDS, одного резервного, `HEALTH_OK` и всех PG в `active+clean`. Пулы CephFS должны иметь `size=3`, `min_size=2`. На Ubuntu 24.04 с ядром 6.8 новый ключ `aes256k` Ceph Tentacle 20.2.5 не принимается kernel client. В этом стенде используйте `ceph-fuse`; не меняйте тип ключа ради монтирования:

```bash
sudo cephadm install ceph-fuse
sudo ceph fs authorize cephfs client.lab / rw >/dev/null
sudo ceph auth get client.lab | sudo tee /etc/ceph/ceph.client.lab.keyring >/dev/null
sudo chmod 600 /etc/ceph/ceph.client.lab.keyring
sudo mkdir -p /mnt/cephfs
sudo ceph-fuse /mnt/cephfs -n client.lab -k /etc/ceph/ceph.client.lab.keyring --client-fs=cephfs
findmnt /mnt/cephfs
echo "CephFS $(date -Is)" | sudo tee /mnt/cephfs/hello.txt
sudo cat /mnt/cephfs/hello.txt
```

Далее выполните [разделы 5–6 основной инструкции](../README.md#5-проверить-отказ-и-данные): сохраните SHA256 до отказа, проверьте файл и запись при остановленной ноде, затем после восстановления запустите `fio`. В облаке для испытания отключайте **ceph2 или ceph3**, на котором в этот момент активен MDS, используя `yc` из Windows:

```powershell
yc compute instance stop --name otus-ceph2
yc compute instance start --name otus-ceph2
```

Выбирайте имя по фактическому выводу `sudo ceph fs status cephfs`. Ceph1 оставляйте работающим, поскольку с него идут проверка и монтирование. При остановке ноды фиксируйте quorum 2/3, OSD 2/3, статус PG, переход MDS и успешную запись. После включения дождитесь `active+clean` и проверьте SHA256. Числа производительности записывайте вместе с конфигурацией ВМ и дисков. Перед удалением стенда: `sudo umount /mnt/cephfs`.

## 5. Сохранить результаты и удалить стенд

Сохраните в `../evidence/` выводы `ceph -s`, `ceph fs status cephfs`, `ceph osd tree`, SHA256 и `fio` без ключей и токенов. В этом запуске в Git добавлены [выдержка отказа](../evidence/failover-console.txt), [итоговый вывод Ceph](../evidence/cluster-final-state.txt), [JSON записи](../evidence/fio-write.json), [JSON чтения](../evidence/fio-read.json) и [проверка удаления](../evidence/cleanup-verification.txt). Затем из этого каталога PowerShell:

```powershell
terraform plan -destroy
terraform destroy
yc compute instance list
yc compute disk list
yc vpc network list
```

Проверьте пустые списки для созданных ВМ, дисков и VPC. Если план удаления не видит ресурсы, проверьте папку, Terraform state и текущий каталог до ручного удаления. После завершения удалите токен из сессии: `Remove-Item Env:YC_TOKEN`.

## Источники

- [Ceph: установка с cephadm](https://docs.ceph.com/en/tentacle/cephadm/install/)
- [Ceph: требования к OSD-диску](https://docs.ceph.com/en/tentacle/cephadm/services/osd/)
- [Ceph: монтирование через FUSE](https://docs.ceph.com/en/tentacle/cephfs/mount-using-fuse/)
- [Ceph: типы ключей и старые kernel clients](https://docs.ceph.com/en/latest/rados/configuration/auth-config-ref/)
- [Ceph: рекомендации по ресурсам](https://docs.ceph.com/en/tentacle/start/hardware-recommendations/)
- [Yandex Cloud: квоты Compute Cloud](https://yandex.cloud/ru/docs/compute/concepts/limits)
- [Yandex Cloud: тарификация Compute Cloud](https://yandex.cloud/ru/docs/compute/pricing)
