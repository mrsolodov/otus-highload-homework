# Веб-приложение с отказоустойчивыми фронтендами и бэкендами

В тексте задания требуется схема: два Nginx с Keepalived, два бэкенда с uWSGI, некластеризованная СУБД и GFS2 для общей статики. Здесь я следую именно этим критериям. За основу взял подготовленный ранее стенд `07-highload-web`.

Для запуска на Windows есть Vagrant и PowerShell-скрипт; службы настраивает Ansible. Саму схему из пяти VM я проверил в GitHub Actions на Ubuntu с libvirt и тем же playbook. Это отдельный способ создать VM для автоматической проверки: Windows-скрипт на моей машине в этом прогоне не запускался.

| ВМ | IP в локальной сети | Роль |
| --- | --- | --- |
| `nginx1` | `192.168.56.11` | Nginx и Keepalived, приоритет 110 |
| `nginx2` | `192.168.56.12` | Nginx и Keepalived, приоритет 100 |
| `app1` | `192.168.56.21` | Python/uWSGI, GFS2 |
| `app2` | `192.168.56.22` | Python/uWSGI, GFS2 |
| `db1` | `192.168.56.30` | PostgreSQL, iSCSI target и третий голос Corosync |

Общий IP — `192.168.56.100`. Запрос `/health` записывает строку в PostgreSQL и возвращает имя бэкенда. Запрос `/static/index.html` читает страницу с общего GFS2-диска. Keepalived передаёт IP второму фронтенду, если Nginx или его проверка приложения перестают отвечать.

## Запуск и проверка

Нужны Windows с VirtualBox и Vagrant, а также WSL Ubuntu с Ansible. Из PowerShell в каталоге этого задания:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\run-local-lab.ps1"
```

Скрипт создаёт временный пароль БД и копирует SSH-ключи ВМ в домашний каталог WSL. Эти файлы исключены из Git. После настройки проверяются БД, общая страница на GFS2, работа с остановленным `app1`, переключение общего IP при остановке Nginx на `nginx1` и восстановление обоих сервисов. Результат будет записан в `evidence/local-lab-results.json` только после фактического запуска. При успешной проверке ВМ удаляются командой `vagrant destroy -f`.

Автоматическая проверка [прошла в GitHub Actions](https://github.com/mrsolodov/otus-highload-homework/actions/runs/40499189415). Результат лежит в [`evidence/ci-lab-results.json`](evidence/ci-lab-results.json). На всех пяти VM Ansible закончил без ошибок; через общий IP подтвердились PostgreSQL и общая статика GFS2. После остановки `app1` отвечал `app2`; после остановки Nginx на `nginx1` общий IP обслуживал `nginx2`. Оба сервиса вернулись в работу, в БД осталось 49 тестовых запросов. В конце CI удалил все пять VM. Полный журнал и [артефакт проверки](https://github.com/mrsolodov/otus-highload-homework/actions/runs/40499189415/artifacts/12731404206) также доступны в запуске.

Чтобы оставить ВМ для осмотра, можно запустить:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\run-local-lab.ps1" -KeepVms
```

После осмотра удалить стенд из этого же каталога:

```powershell
vagrant destroy -f
```

Если проверка завершится ошибкой, скрипт оставит ВМ для диагностики через `vagrant status`, `vagrant ssh` и журналы systemd.

