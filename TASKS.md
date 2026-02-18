# Выполнение заданий курса Kafka

## Задание 1: Развёртывание и настройка Kafka-кластера

### Шаги:

1. **Развернуть Kafka кластер**
    ```bash
    cd terraform
    terraform init
    terraform apply
    ```

2. **Аппаратные ресурсы (в terraform/main.tf):**
    - 3 брокера (s3-c2-m8: 2 CPU, 8 GB RAM)
    - 100 GB network-ssd диск на брокер
    - Schema Registry встроенный (Managed Service)
    - Версия Kafka: 3.9
    - Environment: PRESTABLE

3. **Топик с 3 партициями и репликацией 3**
    - Создается автоматически: `test-topic`
    - Параметры в `terraform/main.tf`

4. **Политика cleanup.policy**
    - Установлена: `delete`
    - retention_ms: 604800000 (~7 дней, 168 часов)
    - retention_bytes: 10737418240 (10 GB)
    - segment_bytes: 268435456 (256 MB)
    - Cleanup policy: CLEANUP_POLICY_DELETE
    - Compression: COMPRESSION_TYPE_LZ4

5. **Schema Registry**
    - Встроенный в Managed Service for Apache Kafka
    - URL: `https://<schema_registry_host>:443`
    - Учетные данные: admin / ваш_пароль
    - Тематика: test-topic-value

6. **Регистрация схемы Product**
    ```bash
    SCHEMA_URL=$(terraform output -raw schema_registry_urls | head -1)
    curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
      -u admin:пароль -k \
      --data @terraform/schemas/product.avsc \
      $SCHEMA_URL/subjects/product-value/versions
    ```

### Скриншоты для отчета:

```bash
# Список Kafka хостов
terraform output kafka_hosts

# Список Schema Registry URLs
terraform output schema_registry_urls

# Список subjects
SCHEMA_URL=$(terraform output -raw schema_registry_urls | head -1)
curl -u admin:пароль -k $SCHEMA_URL/subjects

# Детали схемы
curl -X GET -u admin:пароль -k $SCHEMA_URL/subjects/test-topic-value/versions/latest

# Описание топика
kafka-topics.sh --bootstrap-server <server> \
  --command-config client.properties \
  --topic test-topic --describe
```

### Конфигурация для подключения:
```bash
# Получить bootstrap servers
terraform output kafka_hosts

# Получить Schema Registry URLs
terraform output schema_registry_urls

# Пользователь: admin
# Пароль: из terraform/terraform.tfvars
# Протокол: SASL_SSL
# Механизм: SCRAM-SHA-512
# Порты: 9091 (Kafka), 443 (Schema Registry)
# CA сертификат: скачать из консоли Yandex
```

## Задание 2: Интеграция с Hadoop HDFS (Yandex Data Processing)

### Hadoop развернут через Yandex Data Processing:
- MASTERNODE: 1 нода (s3-c2-m8, 50 GB network-ssd)
- DATANODE: 2 ноды (s3-c2-m8, 50 GB network-ssd)
- Сервисы: HDFS
- Версия: 2.1
- Публичный IP: да на всех узлах
- Порты HDFS:
  - 8020, 9000: NameNode RPC
  - 9870: NameNode Web UI
  - 50010: DataNode transfer
  - 50020: DataNode IPC
  - 50000-51000: High ports for transfer
  - 14000-14001: HTTP FS
  - 50075-50076: DataNode HTTP transfer

### Проверка работы:

```bash
# Получить публичный IP DataProc
terraform output dataproc_master_ips

# NameNode Web UI
http://<dataproc_master_public_ip>:9870

# Подключиться к кластеру
CLUSTER_ID=$(terraform output -raw dataproc_cluster_id)
terraform output dataproc_master_ips
ssh -i ~/.ssh/yandex_cloud ubuntu@<dataproc_master_public_ip>

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
3. Подключитесь к DataProc кластеру через SSH (все узлы имеют публичный IP)
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

4. NameNode Web UI (http://<dataproc_master_public_ip>:9870)

## Структура результатов:

```
/
|-- terraform/
|   |-- main.tf                       # Terraform конфиг инфраструктуры
|   |-- variables.tf                  # Переменные Terraform
|   |-- outputs.tf                    # Выводы Terraform
|-- app/
|   |-- cmd/
|   |   |-- producer/main.go          # Продюсер
|   |   |-- consumer/main.go          # Консьюмер
|   |-- internal/
|   |   |-- domain/product.go         # Логика Product + ProcessProducts
|   |   |-- infra/
|   |   |   |-- clients/
|   |   |   |   |-- kafka/            # Kafka клиент
|   |   |   |   |-- hdfs/             # HDFS клиент
|   |   |-- application/config/       # Конфигурация
|   |-- .env.example                  # Пример конфигурации
|   |-- HDFS_INTEGRATION.md           # Документация интеграции с HDFS
|   |-- docker-compose.yml            # Docker Compose конфиг
|-- README.md                         # Инструкция по развертыванию
|-- TASKS.md                          # Это описание заданий
```

## Примечания:

1. После terraform apply:
    - Kafka кластер создается за 5-10 минут
    - DataProc кластер создается за 10-15 минут

2. Schema Registry сразу доступен по HTTPS на порту 443

3. CA сертификат для SSL: скачайте из консоли Yandex
    `Managed Service for Apache Kafka -> Certificates`

4. Product схема уже обновлена в schemas/product.avsc под вашу структуру

5. DataProc кластер имеет публичные IP на всех узлах - можно подключаться напрямую по SSH
    без использования SSH proxy

6. Для доступа к HDFS внутри кластера используйте `hdfs dfs *` команды на мастер-ноде

7. Security Groups настроены для доступа к:
   - Kafka: порт 9091 (SASL_SSL)
   - Schema Registry: порт 443 (HTTPS)
   - HDFS порты: 8020, 9000, 9870, 50010, 50020, 50000-51000, 14000-14001, 50075-50076
