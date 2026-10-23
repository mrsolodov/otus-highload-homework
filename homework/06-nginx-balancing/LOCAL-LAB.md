# Локальный стенд без квот Yandex Cloud

Этот вариант поднимает четыре отдельные Ubuntu ВМ в VirtualBox. `web1`, `web2`, `web3` обслуживают Nginx, статику и Python/uWSGI; `lb` балансирует запросы между ними. Он использует тот же `ansible/site.yml`, что и облачный вариант. Адреса локальной сети `192.168.77.0/24` можно поменять одновременно в `Vagrantfile` и `ansible/inventory-vagrant.ini`, если она занята.

## Запуск на Windows

Установить VirtualBox и Vagrant для Windows и перезапустить терминал. Затем в обычном PowerShell:

Для запуска всех шагов одной командой, включая проверку балансировки, отказа, запись реальных результатов в `evidence/` и удаление ВМ:

```powershell
Set-Location "D:\Projects\otus-highload-homework\homework\06-nginx-balancing"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\run-local-lab.ps1"
```

Скрипт удаляет локальные ВМ после проверки даже при ошибке; журнал остаётся в `evidence/local-lab-run.txt`. Ниже приведены отдельные команды для ручной диагностики.

```powershell
Set-Location "D:\Projects\otus-highload-homework\homework\06-nginx-balancing"
vagrant --version
VBoxManage --version
vagrant up --provider=virtualbox
vagrant status
```

Vagrant скачает образ `bento/ubuntu-24.04`, создаст ВМ по очереди и запустит Ansible внутри каждой из них. При успешном запуске все четыре машины имеют статус `running`. Планируйте примерно 4 ГБ RAM для гостей плюс память Windows и WSL. Для локальной схемы Terraform и Yandex Cloud не используются.

Если уже были созданы ВМ и менялся только playbook, применить конфигурацию ещё раз:

```powershell
vagrant provision
```

Проверка двух алгоритмов из PowerShell:

```powershell
1..9 | ForEach-Object {
    $r = Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.77.10/rr/api/health"
    "rr: $($r.StatusCode) $($r.Headers['X-Frontend']) $($r.Content.Trim())"
}

1..6 | ForEach-Object {
    $r = Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.77.10/hash/api/health?key=otus"
    "hash: $($r.StatusCode) $($r.Headers['X-Frontend']) $($r.Content.Trim())"
}
```

Первый цикл должен показать несколько разных имён фронтендов. Во втором имя обычно одинаковое при одном `key`. Проверить статику: `Invoke-WebRequest -UseBasicParsing http://192.168.77.10/rr/`.

Проверка отказа одного фронтенда (после успешной первой проверки):

```powershell
vagrant ssh web2 -c "sudo systemctl stop nginx"
1..6 | ForEach-Object {
    $r = Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.77.10/rr/api/health"
    "rr with web2 down: $($r.StatusCode) $($r.Headers['X-Frontend'])"
}
vagrant ssh web2 -c "sudo systemctl start nginx"
```

Сохранить фактические результаты проверки, а затем выключить стенд:

```powershell
vagrant destroy -f
vagrant status
```

VirtualBox может работать медленнее при включённом Windows Hypervisor Platform, который нужен WSL2. Это следует оценить по реальному запуску; отключать WSL2 для этого стенда не требуется. Локальный запуск пока не проверен: у помощника нет доступа к Windows-компьютеру, VirtualBox и его ВМ.
