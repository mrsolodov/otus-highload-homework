# OTUS: Инфраструктура высоконагруженных систем

Здесь я храню практические работы по курсу OTUS «Инфраструктура высоконагруженных систем». Код и результаты проверок лежат в каталоге `homework`; у каждой работы есть свой README с командами запуска и ограничениями стенда.

## Работы

| № | Тема | Где смотреть |
| --- | --- | --- |
| 03 | Виртуальная машина в Yandex Cloud через Terraform, Nginx и cloud-init | [`homework/03-terraform-yandex-cloud`](homework/03-terraform-yandex-cloud/) |
| 05 | Общий диск по iSCSI, multipath и GFS2 на трёх узлах | [`homework/05-iscsi-multipath-gfs2`](homework/05-iscsi-multipath-gfs2/) |
| 06 | Балансировка Nginx: round-robin и consistent hash на локальных ВМ | [ветка `homework/06-nginx-balancing`](https://github.com/mrsolodov/otus-highload-homework/tree/homework/06-nginx-balancing/homework/06-nginx-balancing) |
| 07 | Веб-приложение с двумя фронтендами, двумя бэкендами и PostgreSQL; подготовленный локальный стенд | [ветка `homework/07-highload-web`](https://github.com/mrsolodov/otus-highload-homework/tree/homework/07-highload-web/homework/07-highload-web) |
| 10 | ДЗ урока «Альтернативные балансировщики»: Nginx, Keepalived, два бэкенда, PostgreSQL и GFS2 | [`homework/10-alternative-balancers`](homework/10-alternative-balancers/) |
| 11 | MySQL-кластер Percona XtraDB Cluster из трёх узлов | [`homework/11-mysql-cluster`](homework/11-mysql-cluster/) |
| 12 | PostgreSQL-кластер с Patroni, etcd и HAProxy | [`homework/12-postgresql-cluster`](homework/12-postgresql-cluster/) |

Работы 03, 05, 10, 11 и 12 находятся в `main`; работы 06 и 07 доступны в отдельных ветках.

## Секреты и локальные файлы

Токены, пароли, приватные SSH-ключи, Terraform state и локальные файлы с переменными в Git не добавляются. Там, где для запуска нужны секреты, они создаются локально. Перед запуском или удалением ресурсов стоит прочитать README конкретной работы.
