# Kafka как очередь логов

В этом стенде я поставил Kafka между двумя этапами Logstash. Filebeat читает JSON access log двух Nginx, первый Logstash отправляет события в топик `otus-web-logs`, второй читает его и записывает документы в трёхузловой Elasticsearch. Kibana позволяет смотреть события по времени и фильтровать их по веб-узлу.

Два Nginx здесь служат локальными источниками логов по образцу фронтендов предыдущего веб-проекта. Это отдельный учебный стенд: существующие ВМ из задания 10 он не запускает и их журналы не собирает.

## Запуск

Нужны Docker Engine с Compose v2, Python 3, Bash и curl. Для Linux проверьте `sysctl vm.max_map_count`: Elasticsearch требуется значение не ниже `262144`. В CI настройка выставляется автоматически. Для всех контейнеров понадобится несколько гигабайт свободной памяти.

```bash
bash scripts/run-lab.sh
```

Скрипт поднимет Kafka в режиме KRaft, создаст топик из трёх партиций и шаблон индекса с одной репликой. После первых запросов к обоим Nginx он проверит документы в Elasticsearch и создаст data view в Kibana. Затем остановит читающий Logstash, отправит ещё 12 запросов, проверит рост offset в Kafka и отсутствие новых записей в Elasticsearch. После возврата потребителя он дождётся всех 12 документов. Результат сохраняется в `evidence/cluster-check.txt`.

Проверил стенд в [GitHub Actions](https://github.com/mrsolodov/otus-highload-homework/actions/runs/41616767174). Кластер из трёх узлов был `green`, в Kafka после остановки потребителя offset вырос с 26 до 38. В Elasticsearch в этот момент новых записей не было. После запуска потребителя появилось по шесть записей `/buffered` от каждого веб-узла. Краткий вывод сохранил в [`evidence/ci-verification.txt`](evidence/ci-verification.txt); полный вывод доступен как артефакт запуска Actions.

Логи можно открыть в [Kibana Discover](http://127.0.0.1:15601/app/discover): выбрать **OTUS web logs**, период **Last 15 minutes**, затем фильтровать по `source_host` и `uri`. Порты Elasticsearch (`19200`), Kibana (`15601`) и двух Nginx (`18081`, `18082`) опубликованы только на `127.0.0.1`. Kafka и Logstash доступны лишь внутри сети Compose.

После проверки удалить контейнеры и учебные тома:

```bash
bash scripts/run-lab.sh --destroy
```

Все компоненты работают на одном Docker-хосте. Kafka здесь состоит из одного брокера: остановка потребителя проверяет буферизацию и последующее чтение очереди, но не отказоустойчивость самого брокера или хоста. Внутренний трафик стенда идёт без TLS и аутентификации.

Для конфигурации сверялся с документацией [Kafka output](https://www.elastic.co/guide/en/logstash/8.19/plugins-outputs-kafka.html) и [Kafka input](https://www.elastic.co/guide/en/logstash/8.19/plugins-inputs-kafka.html) Logstash, а также [KRaft в Docker](https://docs.confluent.io/platform/current/installation/docker/config-reference.html).
