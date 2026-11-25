# Локальный вариант Ceph на Proxmox

Практика к занятию 36. Три Ubuntu 24.04 ВМ работают как MON, MGR и OSD; CephFS предоставляет общий POSIX-каталог клиенту. Конфигурация ВМ лежит в [`terraform/`](terraform/). Инструкция ниже рассчитана на отдельный учебный стенд, а не на рабочий кластер.

Этот вариант на Proxmox не запускался: [замеры ёмкости](evidence/capacity-2026-11-25.md) показали, что на текущем компьютере не хватает RAM и дискового места. Фактический трёхузловой кластер был развёрнут в [Yandex Cloud](yandex-cloud/README.md), а его [результаты](evidence/yandex-cloud-2026-11-25.md) сохранены отдельно. Инструкция ниже пригодится на более ёмком локальном хосте.

## Архитектура

```text
CephFS-клиент ──► MON (карта кластера, quorum 2/3)
       │          MDS (метаданные; активный + резервный)
       └────────► OSD × 3 (данные в RADOS, по диску на узел)
                    └─ CRUSH: три копии на разных хостах
MGR управляет кластером и cephadm; MON не хранит пользовательские файлы.
```

CephFS хранит метаданные и файлы в разных пулах RADOS. Клиент получает карту от MON, обращается к MDS за метаданными и читает/пишет данные через OSD. При `size=3`, `min_size=2` потеря одного OSD оставляет запись доступной, но кластер будет `HEALTH_WARN` до восстановления третьей копии. Это учебная модель: все ВМ на одном физическом хосте не защищают от его отказа.

## Ресурсы и адреса

| Узел | VM ID | IP | Роли | Диски |
| --- | ---: | --- | --- | --- |
| ceph1 | 9136 | 172.28.19.36 | MON, MGR, OSD, клиент | 20 ГиБ ОС + 20 ГиБ OSD |
| ceph2 | 9137 | 172.28.19.37 | MON, MGR standby, OSD, MDS | 20 ГиБ ОС + 20 ГиБ OSD |
| ceph3 | 9138 | 172.28.19.38 | MON, OSD, MDS standby | 20 ГиБ ОС + 20 ГиБ OSD |

Каждой ВМ в исходной конфигурации назначены 2 vCPU и 4 ГиБ RAM. Это **только экспериментальный учебный минимум**: официальные рекомендации Ceph учитывают память каждого OSD, MON и MDS отдельно и требуют дополнительный запас на ОС и восстановление. Для осмысленных тестов надёжности и скорости понадобится существенно больше памяти. Три ВМ по 4 ГиБ уже требуют 12 ГиБ **внутри** Proxmox плюс запас самому Proxmox и Windows; на этом компьютере такой профиль недоступен. Диски занимают около 120 ГиБ виртуальной ёмкости и место под образ Ubuntu, тогда как весь текущий `local-lvm` имеет лишь около 20,7 ГиБ. Три ВМ создаются в отдельном Terraform state и не меняют ВМ заданий 19/31/33.

Все узлы должны видеть друг друга по TCP 3300/6789 (MON), TCP 6800–7568 (OSD/MDS/MGR), TCP 22 (cephadm SSH), иметь синхронное время и доступ к пакетам Ceph и контейнерному registry. Порты открывайте только внутри учебной подсети. Сеть одна, поэтому отдельный `cluster_network` здесь не задаётся.

## 1. Создать ВМ

Нужны работающий Proxmox VE с `local`, `local-lvm`, `vmbr0`, API-токеном для Terraform, Terraform 1.7+ и публичный SSH-ключ. Из PowerShell в каталоге `terraform/`:

```powershell
$env:PROXMOX_VE_ENDPOINT = 'https://172.28.19.2:8006/'
$env:PROXMOX_VE_API_TOKEN = Read-Host 'Proxmox API token'
$env:TF_VAR_node_name = 'pve' # заменить фактическим именем узла
$env:TF_VAR_ssh_public_key = (Get-Content "$HOME\.ssh\id_ed25519.pub" -Raw).Trim()
terraform init
terraform plan -out=ceph.tfplan
terraform apply ceph.tfplan
terraform output virtual_machines
```

При самоподписанном сертификате в этом локальном стенде можно задать `$env:PROXMOX_VE_INSECURE = 'true'`. План перед применением должен показать ровно три новые ВМ и по два диска у каждой. VM ID, адреса, storage и объём памяти можно поменять через `terraform.tfvars` (файл исключён из Git). Оба диска создаются в Proxmox; OSD-диск должен остаться без разделов, ФС и LVM. Не используйте диск ОС для OSD. После запуска проверьте SSH с Windows на `.36`, `.37`, `.38`.

## 2. Подготовить все три Ubuntu

На каждой ВМ по SSH (замените `ceph1` на соответствующее имя):

```bash
sudo hostnamectl set-hostname ceph1
sudo tee -a /etc/hosts >/dev/null <<'EOF'
172.28.19.36 ceph1
172.28.19.37 ceph2
172.28.19.38 ceph3
EOF
sudo apt-get update
sudo apt-get install -y docker.io lvm2 chrony openssh-server cephadm
sudo systemctl enable --now docker chrony ssh
sudo cephadm check-host
bash /tmp/check-node.sh
```

Скрипт `check-node.sh` сначала скопируйте на каждую ВМ, например из PowerShell `scp -i $HOME\.ssh\id_ed25519 scripts/check-node.sh ubuntu@172.28.19.36:/tmp/` и запустите `bash /tmp/check-node.sh`; повторите для `.37` и `.38`. Он только читает состояние. Проверьте, что `hostname` возвращает имя узла, часы синхронизированы, адреса доступны и отдельный диск виден в `lsblk`. У virtio-диска это обычно `/dev/vdb`, но перед каждым шагом с OSD сверяйте путь с `lsblk` и `ceph orch device ls --wide`. В существующем стенде DNS внутри ВМ ранее работал нестабильно; при сбое `apt` или загрузки контейнера сначала восстановите DNS и доступ к registry.

## 3. Развернуть кластер

На **ceph1** установите актуальную ветку Tentacle через `cephadm` и создайте первый MON/MGR:

```bash
sudo cephadm add-repo --release tentacle
sudo cephadm install
sudo cephadm bootstrap --mon-ip 172.28.19.36 --ssh-user ubuntu
sudo cephadm install ceph-common ceph-fuse
sudo ceph -s
```

Версию после установки проверьте через `ceph version`; инструкция рассчитана на поддерживаемую ветку 20.2.x. На Windows скопируйте публичный ключ cephadm к пользователю `ubuntu` на ceph2/ceph3, используя **свой** ключ для исходного SSH-доступа:

```powershell
$sshKey = "$HOME\.ssh\id_ed25519"
$cephPub = (& ssh.exe -i $sshKey ubuntu@172.28.19.36 'cat /etc/ceph/ceph.pub').Trim()
if ($LASTEXITCODE -ne 0 -or -not $cephPub.StartsWith('ssh-')) { throw 'Could not read cephadm public key' }
foreach ($ip in @('172.28.19.37', '172.28.19.38')) {
    $cephPub | & ssh.exe -i $sshKey "ubuntu@$ip" 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
    if ($LASTEXITCODE -ne 0) { throw "Key copy failed on $ip" }
}
```

На **ceph1** добавьте хосты и задайте размещение демонов:

```bash
sudo ceph orch host add ceph2 172.28.19.37
sudo ceph orch host add ceph3 172.28.19.38
sudo ceph orch apply mon --placement='3 ceph1 ceph2 ceph3'
sudo ceph orch apply mgr --placement='2 ceph1 ceph2'
sudo ceph orch host ls
sudo ceph orch ps --daemon-type mon
```

Дождитесь трёх MON и quorum 3/3. На **ceph1** посмотрите инвентаризацию дисков:

```bash
sudo ceph orch device ls --wide --refresh
sudo ceph orch apply osd --all-available-devices --dry-run
```

В dry run должны быть только **три выделенных OSD-диска**, по одному на хост. Если есть лишние доступные диски, не применяйте `--all-available-devices`: укажите проверенные пути по одному. Пример ниже предполагает, что на всех ВМ OSD-диск действительно `/dev/vdb`:

```bash
sudo ceph orch daemon add osd ceph1:/dev/vdb
sudo ceph orch daemon add osd ceph2:/dev/vdb
sudo ceph orch daemon add osd ceph3:/dev/vdb
sudo ceph osd tree
sudo ceph -s
```

Эта операция перезапишет содержимое **указанных** дисков. Ждите `3 up, 3 in`; не продолжайте при ошибках `ceph orch device ls --wide`.

## 4. CephFS и клиент

На **ceph1** создайте ФС, задайте два MDS и проверьте пулы:

```bash
sudo ceph fs volume create cephfs
sudo ceph orch apply mds cephfs --placement='2 ceph2 ceph3'
sudo ceph fs status cephfs
sudo ceph fs dump
sudo ceph osd pool ls detail
```

Проверьте, что у обоих пулов CephFS `size=3`, `min_size=2`, три OSD размещены на разных хостах (`ceph osd tree`), а MDS имеет активный и резервный экземпляры. Не ослабляйте `min_size` ради красивого `HEALTH_OK`.

На **ceph1** создайте ограниченного CephX-клиента и смонтируйте CephFS через `ceph-fuse`:

```bash
sudo ceph fs authorize cephfs client.lab / rw >/dev/null
sudo ceph auth get client.lab | sudo tee /etc/ceph/ceph.client.lab.keyring >/dev/null
sudo chmod 600 /etc/ceph/ceph.client.lab.keyring
sudo mkdir -p /mnt/cephfs
sudo ceph-fuse /mnt/cephfs -n client.lab -k /etc/ceph/ceph.client.lab.keyring --client-fs=cephfs
findmnt /mnt/cephfs
echo "CephFS $(date -Is)" | sudo tee /mnt/cephfs/hello.txt
sudo cat /mnt/cephfs/hello.txt
```

Для отдельного клиента нужны `ceph-fuse`, конфигурация MON и этот ограниченный keyring. Административный keyring и содержимое клиентского keyring в Git и отчёт не добавляйте. Ceph Tentacle 20.2.5 по умолчанию создал новый ключ `aes256k`; kernel client Ubuntu 24.04 с ядром 6.8 его не принимает. `ceph-fuse` успешно работает с ним без понижения типа ключа. В конце работы: `sudo umount /mnt/cephfs`.

## 5. Проверить отказ и данные

Сначала на **ceph1** запишите проверочный файл и хеш вне CephFS:

```bash
sudo dd if=/dev/urandom of=/mnt/cephfs/check.bin bs=1M count=64 status=progress conv=fsync
sudo sha256sum /mnt/cephfs/check.bin | sudo tee /tmp/ceph-check.before.sha256
sudo ceph -s
```

В `sudo ceph fs status cephfs` найдите хост активного MDS: это должен быть **ceph2** или **ceph3**. Выключите именно его через гипервизор (не удаляйте ВМ или диск). После обнаружения отказа на ceph1 проверьте `sudo ceph -s`: ожидаются 2/3 MON quorum, 2/3 OSD up, degraded PG, переход резервного MDS в active и работающий CephFS. Выполните:

```bash
sudo sha256sum -c /tmp/ceph-check.before.sha256
echo "write during failure $(date -Is)" | sudo tee /mnt/cephfs/during-failure.txt
sudo cat /mnt/cephfs/during-failure.txt
sudo ceph health detail
```

Включите выключенный узел обратно. Дождитесь возврата OSD, MON и MDS и восстановления всех PG до `active+clean`:

```bash
sudo ceph -s
sudo ceph osd tree
sudo ceph pg stat
sudo sha256sum -c /tmp/ceph-check.before.sha256
```

Один отказ подтверждает доступность и целостность в этом сценарии, но не доказывает защиту от двух одновременных отказов, сбоя физического хоста или долговременную надёжность.

## 6. Измерить скорость

На ceph1 установите `fio` и выполните последовательные запись/чтение на смонтированной ФС. Результат имеет смысл только вместе с описанием ВМ, дисков и состояния кластера; вложенная виртуализация и один физический диск ограничивают интерпретацию.

```bash
sudo apt-get install -y fio
sudo fio --name=cephfs-write --filename=/mnt/cephfs/fio.bin --rw=write --bs=1M --size=256M --direct=1 --ioengine=sync --iodepth=1 --group_reporting --output=/tmp/cephfs-write.json --output-format=json
sudo fio --name=cephfs-read --filename=/mnt/cephfs/fio.bin --rw=read --bs=1M --size=256M --direct=1 --ioengine=sync --iodepth=1 --group_reporting --output=/tmp/cephfs-read.json --output-format=json
sudo rm /mnt/cephfs/fio.bin
```

В JSON смотрите `bw_bytes`, `iops`, задержки `clat_ns` и ошибки. Не проводите нагрузочный тест при degraded PG. Для отчёта скопируйте `scripts/check-cluster.sh` на ceph1 и сохраните его вывод, хеш до/после, результаты `fio` и последовательность выключения/включения узла. До фактического запуска числовых результатов нет.

## Источники

- [cephadm: установка и bootstrap](https://docs.ceph.com/en/tentacle/cephadm/install/)
- [Добавление хостов и SSH-ключ cephadm](https://docs.ceph.com/en/tentacle/cephadm/host-management/)
- [Выбор и добавление OSD-дисков](https://docs.ceph.com/en/tentacle/cephadm/services/osd/)
- [Создание CephFS volume](https://docs.ceph.com/en/tentacle/cephfs/fs-volumes/)
- [Монтирование CephFS через FUSE](https://docs.ceph.com/en/tentacle/cephfs/mount-using-fuse/)
- [Совместимость CephX-ключей с kernel client](https://docs.ceph.com/en/latest/rados/configuration/auth-config-ref/)
- [Рекомендации Ceph по аппаратным ресурсам](https://docs.ceph.com/en/tentacle/start/hardware-recommendations/)
