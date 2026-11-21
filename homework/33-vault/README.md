# HashiCorp Vault: портал в Nomad

Для этого ДЗ я взял вторую Ubuntu ВМ из [задания 19](../19-proxmox/). На ней Nomad запускает два экземпляра портала, три узла Vault держат общее храниллище секретов, а PostgreSQL выдаёт временный доступ к базе.

Пароль действует не дольше 120 секунд. Когда Nomad получает новую пару приложение читает её из файла без перезапсука. На странице виден только отпечаток пользователя БД, сам пароль туда не попадает.

## Запуск

Нужны Docker с Compose, Nomad и Vault CLI на Ubuntu. Команды выполняются из каталога этого задания. Пароль для PostgreSQL создаётся локально и в Git не попадает.

```bash
if [ ! -f .env ]; then
  printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)" > .env
  chmod 600 .env
fi
docker compose up -d
bash scripts/allow-local-ports.sh
python3 scripts/bootstrap-vault.py
if ! systemctl is-active --quiet otus33-nomad; then
  sudo systemd-run --unit=otus33-nomad /usr/bin/nomad agent -config="$PWD/nomad/agent.hcl"
fi
until nomad node status | grep -q ready; do sleep 2; done
python3 scripts/configure-local.py
docker build -t otus-portal:33 app
nomad job run nomad/portal.nomad.hcl
```

На моём стенде DNS внутри ВМ иногда не отвечал поэтому адреса Docker Hub пришлось добавить в /etc/hosts. K3s из предыдущего ДЗ оставил правило INPUT DROP; скрипт allow-local-ports.sh открывает нужные порты только для Docker-подсетей.

## Проверка

```bash
nomad job status otus-portal
nomad service info otus-portal
python3 scripts/collect-cluster.py
python3 scripts/collect-portal-logs.py
python3 scripts/verify-rotation.py http://HOST:PORT/
```

HOST:PORT возьмите из вывода Nomad. Проверка ротации идёт 4,5 минуты. На моём запуске три узла Vault вошли в Raft-кластер, оба экземпляра портала остались healthy. [Снимок кластера](evidence/cluster.txt), [логи приложения](evidence/portal-logs.txt) и [проверка ротации](evidence/rotation.txt) лежат рядом: 27 запросов ответили 200, приложение успело сменить четырёх пользователей БД. Фактическая смена происходила раньше конца двухминутного lease.
