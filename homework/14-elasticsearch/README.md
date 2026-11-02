# Централизованный сбор логов в Elasticsearch

Для этого задания я поднял три узла Elasticsearch, Filebeat и Kibana. Источники логов — два Nginx, как два фронтенда веб-проекта из предыдущих работ. В этом локальном стенде они отвечают простой страницей и пишут access log в JSON. Filebeat читает оба файла и отправляет события в общий индекс.

## Запуск

Нужны Docker Engine с Compose v2, Python 3, Bash и curl. Для Elasticsearch на Linux требуется `vm.max_map_count` не меньше `262144`; проверить можно командой `sysctl vm.max_map_count`. На время работы стенда нужно около 5–6 ГБ свободной памяти.

Из этого каталога:

```bash
bash scripts/run-lab.sh
```

Скрипт сначала ждёт три узла, затем создаёт шаблон индекса с одним основным шардом и одной репликой. После этого он отправляет запросы на оба фронтенда, проверяет документы в Elasticsearch, создаёт data view в Kibana, отключает один узел с копией шарда и повторяет запись и чтение логов. В конце возвращает узел и проверяет состояние кластера. Если проверка прерывается, контейнеры остаются для диагностики.

Открыть логи можно в [Kibana Discover](http://127.0.0.1:15601/app/discover): выбрать **OTUS web logs**, поставить период **Last 15 minutes**, затем фильтровать по `source_host: web1`, `source_host: web2`, `status` или `uri`. В Discover видны записи и график числа событий во времени. Elasticsearch API доступен на `http://127.0.0.1:19200`, фронтенды — на портах `18081` и `18082`.

После проверки удалить контейнеры и тома с учебными данными:

```bash
bash scripts/run-lab.sh --destroy
```

## Что лежит в каталоге

- `compose.yaml` — три узла Elasticsearch, два Nginx, Filebeat и Kibana;
- `nginx/default.conf` — формат access log с именем веб-узла;
- `filebeat/filebeat.yml` — чтение двух журналов и отправка в Elasticsearch;
- `elasticsearch/index-template.json` — настройки индекса и полей;
- `scripts/run-lab.sh` — запуск и проверка отказа узла;
- `evidence/cluster-check.txt` — вывод успешного запуска, если стенд проверен.

Контейнеры находятся на одном Docker-хосте. Остановка одного контейнера проверяет репликацию и сохранение кворума, но не защищает от потери самого хоста. Для локальной лабораторной работы TLS и аутентификация Elasticsearch отключены, а опубликованные порты доступны только с `127.0.0.1`. При запуске на отдельном сервере или в публичной сети эту конфигурацию нужно менять.

Проверка [прошла в GitHub Actions](https://github.com/mrsolodov/otus-highload-homework/actions/runs/41495494148). До отказа было по 13 записей от каждого веб-узла; после остановки `es2` кластер остался зелёным с двумя узлами и двумя активными шардами, а количество записей выросло до 17 на источник. После возврата `es2` кластер снова стал трёхузловым. [Краткий вывод](evidence/ci-summary.txt) лежит рядом с конфигурацией, полный журнал доступен в артефакте CI.

Использовал документацию [Elastic по многосерверному запуску через Compose](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-compose), [filestream/ndjson](https://www.elastic.co/guide/en/beats/filebeat/8.19/filebeat-input-filestream.html) и [API data view в Kibana](https://www.elastic.co/docs/api/doc/kibana/operation/operation-createdataviewdefaultw).
