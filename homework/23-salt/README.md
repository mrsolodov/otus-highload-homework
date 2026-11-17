# Salt: Nginx и iptables на двух серверах

После задания с Proxmox у меня остались две Ubuntu 24.04 ВМ: `app1` (`172.28.19.10`) и `app2` (`172.28.19.11`). В этой работе я настроил их через Salt. Master работает на `app1`, minion установлен на обеих машинах. Salt ставит Nginx, отдаёт страницу с именем узла и задаёт правила iptables.

## Запуск

Сначала нужны ВМ из [задания 19](../19-proxmox/) со статическими адресами, указанными в его README, и входом по SSH-ключу для пользователя `ubuntu`. На Windows нужны PowerShell 5.1+ и OpenSSH. Из каталога этого задания:

```powershell
.\deploy.ps1 -SshKey "$HOME\.ssh\id_ed25519"
```

Если адреса или пользователь отличаются, их можно задать через `-MasterIp`, `-Web2Ip` и `-SshUser`. Скрипт устанавливает Salt 3008, копирует состояния на master, принимает ключи `web1` и `web2` и применяет конфигурацию. Потом он запускает highstate ещё раз: во второй раз изменений быть не должно. В конце проверяет `/health` на обоих серверах.

На моём стенде DNS внутри ВМ работал нестабильно. Поэтому перед установкой скрипт получает адреса Ubuntu-зеркал, GitHub и репозитория Salt через DNS Windows и обновляет записи в `/etc/hosts` гостевых систем.

## Проверка

С master можно повторить основные команды вручную:

```bash
sudo salt 'web*' test.ping
sudo salt 'web*' state.highstate
sudo salt 'web*' cmd.run 'systemctl is-active nginx && iptables -S INPUT'
```

Страницы доступны по адресам `http://172.28.19.10/` и `http://172.28.19.11/`. На каждой показан ID её minion; `/health` отвечает `ok`.

Оба minion ответили master, Nginx работает на обеих ВМ, а повторный highstate завершился без изменений. У iptables установлена политика `INPUT DROP`: разрешены SSH, HTTP, ICMP, loopback и уже установленные соединения. На `web1` также открыты порты Salt 4505 и 4506. Правила сохранились в `/etc/iptables/rules.v4`; проверка `iptables-restore --test` прошла на обеих ВМ. [Краткий вывод проверки](evidence/lab-verification.txt) оставил рядом с конфигурацией.

Стенд использует только IPv4-правила iptables; IPv6 здесь отдельно не фильтруется. Скрипт не создаёт и не удаляет ВМ. Удалять их нужно через Terraform из задания 19.

Документация: [установка Salt на Ubuntu](https://docs.saltproject.io/salt/install-guide/en/latest/topics/install-by-operating-system/linux-deb.html), [состояния iptables](https://docs.saltproject.io/en/latest/ref/states/all/salt.states.iptables.html).
