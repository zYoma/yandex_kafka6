# Выполнение заданий курса Kafka

## Задание 1: Развёртывание и настройка Kafka-кластера

### Шаги:

1. **Развернуть Kafka кластер**
   ```bash
   terraform init
   terraform apply
   ```

2. **Аппаратные ресурсы (в main.tf):**
   - 3 брокера (s3-c2-m8: 2 CPU, 8 GB RAM)
   - 100 GB network-ssd диск на брокер
   - Schema Registry встроенный (Managed Service)

3. **Топик с 3 партициями и репликацией 3**
   - Создается автоматически: `test-topic`
   - Параметры в `main.tf`

4. **Политика cleanup.policy**
   - Установлена: `delete`
   - log.retention.ms: 259200000 (72 часа)
   - log.segment.bytes: 1073741824 (1 GB)

5. **Schema Registry**
   - Встроенный в Managed Service for Apache Kafka
   - URL: `https://<schema_registry_host>:443`
   - Учетные данные: admin / ваш_пароль

6. **Регистрация схемы Product**
   ```bash
   SCHEMA_URL=$(terraform output -raw schema_registry_url)
   curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
     -u admin:пароль -k \
     --data @schemas/product.avsc \
     $SCHEMA_URL/subjects/product-value/versions
   ```

### Скриншоты для отчета:

```bash
SCHEMA_URL=$(terraform output -raw schema_registry_url)

# Список subjects
curl -u admin:пароль -k $SCHEMA_URL/subjects

# Детали схемы
curl -X GET -u admin:пароль -k $SCHEMA_URL/subjects/product-value/versions

# Описание топика
kafka-topics.sh --bootstrap-server <server> \
  --command-config client.properties \
  --topic test-topic --describe
```

### Конфигурация для подключения:
```bash
# Получить bootstrap servers
terraform output kafka_bootstrap_servers

# Пользователь: admin
# Пароль: из terraform.tfvars
# Протокол: SASL_SSL
# Механизм: SCRAM-SHA-512
# CA сертификат: скачать из консоли Yandex
```

## Задание 2: Интеграция с Hadoop HDFS (Yandex Data Processing)

### Hadoop развернут через Yandex Data Processing:
- MASTERNODE: 1 нода (s3-c2-m8)
- DATANODE: 2 ноды (s3-c2-m8)
- Сервисы: HDFS, ZooKeeper (минимум для задания 2)

### Проверка работы:

```bash
# Получить публичный IP DataProc
yc dataproc cluster get $(terraform output -raw dataproc_cluster_id) --format json | \
  jq -r '.host[] | select(.subcluster_role=="MASTERNODE") | .name, .assign_public_ip'

# YARN Web UI
http://<dataproc_master_public_ip>:8088

# NameNode Web UI
http://<dataproc_master_public_ip>:9870

# Подключиться к кластеру
CLUSTER_ID=$(terraform output -raw dataproc_cluster_id)
yc dataproc cluster ssh $CLUSTER_ID --host <hostname> --ssh-key ~/.ssh/yandex_cloud

# HDFS команды
hdfs dfs -ls /
hdfs dfs mkdir /kafka_data

# Передача данных из Kafka в HDFS:
# Используйте ваш продюсер для записи в Kafka
# Затем чтение из Kafka и запись в HDFS
hdfs dfs -put /path/to/local/file /kafka_data/
hdfs dfs -cat /kafka_data/file
```

### Интеграция Kafka -> HDFS:

В вашем продюсере/консьюмере (app/):
1. Читайте сообщения из Kafka с использованием Product схемы
2. Записывайте их в локальный файл
3. Подключитесь к DataProc кластеру через `yc dataproc cluster ssh`
4. Загрузите файл в HDFS

```
Пример потока:
Kafka Producer (Product) -> Kafka Topic (test-topic) -> Kafka Consumer (Product schema) -> Локальный файл -> HDFS
```

### Скриншоты для отчета задания 2:

1. Запущенные сервисы DataProc:
   ```bash
   yc dataproc cluster list
   yc dataproc cluster get <cluster_id>
   ```

2. Конфигурационные файлы из main.tf

3. Логи успешной передачи данных:
   - `hdfs dfs -ls /kafka_data`
   - `hdfs dfs -cat /kafka_data/<file>`
   - kafka-console-consumer.sh логи

## Структура результатов:

```
/
|-- schemas/
|   |-- product.avsc            # Файл схемы Product для задания 1
|-- scripts/
|   |-- register-schema.sh      # Скрипт регистрации схемы
|-- app/                        # Ваши файлы продюсера/консьюмера
|   |-- producer.go             # Ваш продюсер
|   |-- consumer.go             # Ваш консьюмер
|-- main.tf                     # Terraform конфиг
|-- README.md                   # Инструкция
|-- TASKS.md                    # Это описание
```

## Примечания:

1. После terraform apply:
   - Kafka кластер создается за 5-10 минут
   - DataProc кластер создается за 10-15 минут
   
2. Schema Registry сразу доступен по HTTPS на порту 443

3. CA сертификат для SSL: скачайте из консоли Yandex
   `Managed Service for Apache Kafka -> Certificates`

4. Product схема уже обновлена в schemas/product.avsc под вашу структуру

5. DataProc кластер использует SSH proxy на порту 50105 для подключения

6. Для доступа к HDFS внутри кластера используйте `hdfs dfs *` команды на мастер-ноде
