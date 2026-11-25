# Задание 36: результаты Ceph в Yandex Cloud, 25.11.2026

## Стенд

Terraform создал 11 ресурсов в каталоге `otus-highload`: три ВМ `standard-v3` по 2 vCPU и 16 ГиБ RAM в `ru-central1-a`, `ru-central1-d`, `ru-central1-e`; у каждой 20-ГиБ HDD для ОС и отдельный 10-ГиБ `network-ssd` для OSD; отдельную VPC, три подсети и группу безопасности. Для доступа SSH использовался один фактический внешний IP `/32`. До запуска папка не содержала ВМ и дисков.

На Ubuntu 24.04 установлен Ceph Tentacle 20.2.5 через `cephadm`. Сеть кластера: `10.136.0.0/16`; MON: по одному на каждом хосте; MGR: активный на ceph1 и резервный на ceph2; OSD: по одному `/dev/vdb` на хосте. CephFS имеет активный MDS на ceph2 и резервный на ceph3 до отказа. Пулы данных и метаданных: `size=3`, `min_size=2`.

Перед испытанием: `HEALTH_OK`, quorum MON 3/3, OSD 3 up/3 in, один активный и один резервный MDS, **81 PG `active+clean`**. CephFS смонтирована на ceph1 через `ceph-fuse` с ограниченным `client.lab`. Запись и чтение `hello.txt` успешны.

Попытка kernel mount с новым ключом CephX `aes256k` завершилась `adding ceph secret key to kernel failed: Invalid argument`. У ВМ ядро 6.8; согласно [документации Ceph по ключам](https://docs.ceph.com/en/latest/rados/configuration/auth-config-ref/) поддержка `aes256k` в kernel client появилась в Linux 7.0. Для работы использован [Ceph FUSE client](https://docs.ceph.com/en/tentacle/cephfs/mount-using-fuse/) без замены ключа на старый тип.

## Отказ ceph2 и восстановление

До остановки ceph2 записан файл 64 МиБ `/mnt/cephfs/check.bin`. SHA256:

```text
3f0b1c99a48cdd19cd21d12082e13a0f070e0034d0ba61494d5f118cdeafca8f
```

Остановлена именно ceph2, на которой находился активный MDS. После обнаружения отказа: quorum MON **2/3** (ceph1, ceph3), OSD **2/3 up**, 81 PG `active+undersized` либо `active+undersized+degraded`, 42/126 объектов временно деградировали. Резервный MDS на **ceph3 стал active**. На уже смонтированной CephFS `sha256sum -c` вернул `OK`; запись и чтение `during-failure.txt` прошли успешно. [Выдержка из терминала во время отказа](failover-console.txt) сохранена отдельно.

После включения ceph2: `HEALTH_OK`, quorum MON **3/3**, OSD **3 up/3 in**, активный MDS остался на ceph3, ceph2 стал резервным. Все **81 PG `active+clean`**, повторная проверка SHA256 — `OK`.

Это проверка одного сценария отказа. Она не оценивает два одновременных отказа, долгосрочную сохранность или производительность под рабочей нагрузкой.

## Скорость после восстановления

`fio` запущен на ceph1 через смонтированную CephFS после возврата `HEALTH_OK`: файл 256 МиБ, блок 1 МиБ, `direct=1`, `ioengine=sync`, `iodepth=1`, по одному прогону записи и чтения. В обоих JSON `error=0`.

| Операция | Время | Пропускная способность | IOPS | Средняя задержка завершения |
| --- | ---: | ---: | ---: | ---: |
| Последовательная запись | 40,445 с | **6,33 МиБ/с** | 6,33 | 157,92 мс |
| Последовательное чтение | 14,153 с | **18,09 МиБ/с** | 18,09 | 55,27 мс |

Эти числа относятся к небольшим сетевым дискам Yandex Cloud, трём копиям между зонами и FUSE-клиенту. По одному прогону нельзя оценивать разброс или переносить результат на другие конфигурации. Исходные результаты: [запись](fio-write.json), [чтение](fio-read.json), [итоговый вывод Ceph](cluster-final-state.txt).

## Очистка

После теста временный файл `fio.bin` удалён, CephFS размонтирована. Terraform plan показал `0 add, 0 change, 11 destroy`; `terraform apply` завершился `11 destroyed`. Последующие `yc compute instance list`, `yc compute disk list` и `yc vpc network list` вернули `[]`; `terraform state list` пуст. [Повторная проверка очистки](cleanup-verification.txt) сохранена в Git. Облачный стенд больше не тарифицируется.
