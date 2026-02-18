# Интеграция Kafka с Hadoop HDFS в Yandex Cloud

## Обзор

Данное решение реализует интеграцию Apache Kafka с Hadoop HDFS через Yandex Cloud:
- **Kafka**: Managed Service for Apache Kafka со встроенным Schema Registry
- **HDFS**: Yandex Data Processing (Data Proc кластер)
- **Продюсер**: Отправляет JSON сообщения с Product схемой в Kafka
- **Консьюмер**: Читает пачки сообщений, обрабатывает и записывает в HDFS

## Архитектура

```
Producer -> Kafka (JSON Schema Registry) -> Consumer -> HDFS
                 |
                 v
          Yandex Managed Kafka
                 |
                 v
          DataProc (HDFS)
```

## Инфраструктура

### Network
- **VPC**: infra-network
- **Subnet**: 10.0.0.0/24
- **NAT Gateway**: nat-gateway для доступа в интернет

### Kafka Cluster
- **Версия**: 3.9 (PRESTABLE)
- **Брокеры**: 3 узла (s3-c2-m8: 2 CPU, 8 GB RAM, 100 GB)
- **Порты**: 9091 (SASL_SSL), 443 (Schema Registry HTTPS)
- **Публичный IP**: да

### DataProc Cluster
- **Версия**: 2.1
- **MASTERNODE**: 1 узел (s3-c2-m8, 50 GB)
- **DATANODE**: 2 узла (s3-c2-m8, 50 GB)
- **Сервисы**: HDFS
- **Публичный IP**: да на всех узлах
- **Порты HDFS**:
  - 8020, 9000: NameNode RPC
  - 9870: NameNode Web UI
  - 50010: DataNode transfer
  - 50020: DataNode IPC
  - 50000-51000: High ports for transfer
  - 14000-14001: HTTP FS
  - 50075-50076: DataNode HTTP transfer

### Security Groups
- **infra-sg**: Kafka (9091, 443), SSH (22)
- **dataproc-sg**: HDFS порты, SSH (22), внутренний трафик

## Структура проекта

```
app/
├── internal/
│   ├── application/
│   │   ├── config/           # Конфигурация приложения
│   │   ├── interfaces/       # Интерфейсы (Producer, Consumer, HDFSClient)
│   │   └── app.go            # Приложения ProducerApp и ConsumerApp
│   ├── domain/
│   │   └── product.go        # Логика Product + ProcessProducts(в HDFS)
│   └── infra/
│       ├── clients/
│       │   ├── kafka/        # Kafka продюсер/консьюмер + Schema Registry
│       │   └── hdfs/         # HDFS клиент для записи в DataProc
├── cmd/
│   ├── producer/main.go      # Запуск продюсера
│   └── consumer/main.go      # Запуск консьюмера с интеграцией HDFS
└── .env.example              # Пример конфигурации
```

## Запуск

### 1. Развернуть инфраструктуру в Yandex Cloud

```bash
cd terraform
terraform init
terraform apply
```

### 2. Получить параметры

```bash
# Kafka bootstrap servers
terraform output kafka_hosts

# Schema Registry URLs
terraform output schema_registry_urls

# DataProc кластера
terraform output dataproc_cluster_id
terraform output dataproc_master_ips
```

### 3. Скачать CA сертификат

Консоль Yandex -> Managed Service for Apache Kafka -> Сертификаты -> Скачать
Сохранить как `app/certs/CACerts.pem`

### 4. Настроить .env

```bash
cd app
cp .env.example .env
# Отредактировать:
# BOOTSTRAP_SERVER=<terraform output kafka_hosts>
# SCHEMA_REGISTRY_SERVICE_URL=<terraform output schema_registry_urls | head -1>
# SASL_PASSWORD=<ваш_пароль>
# HDFS_ADDRESSES=<terraform output dataproc_master_ips>
```

### 5. Запуск продюсера

```bash
# Отправляет 10,000 продуктов в Kafka (автоматически регистрирует JSON Schema)
docker-compose up producer
# или
go run cmd/producer/main.go
```

### 6. Запуск консьюмера

```bash
# Читает пачки сообщений, обрабатывает и пишет в HDFS
docker-compose up consumer
# или
go run cmd/consumer/main.go
```

## Интеграция с HDFS (Задание 2)

### Как работает:

1. **Consumer** читает пачки сообщений из Kafka
2. **ProcessProducts** в `domain/product.go`:
   - Имитирует обработку (time.Sleep)
   - Вызывает `hdfsClient.WriteProductBatch()` для записи в HDFS
   - Записывает CSV файл с продуктами

3. **HDFS Client** в `infra/clients/hdfs/factory.go`:
   - Создает подключение к DataProc HDFS
   - Записывает данные в формате CSV
   - Файлы создаются по таймстемпу: `products_batch_<timestamp>.csv`

### Переменные окружения для HDFS:

```
HADOOP_HDFS_MODE=true           # true - использовать настоящий HDFS, false - локальный stub
HDFS_ADDRESSES=<dataproc_master_ips>  # Публичный IP DataProc
HDFS_KAFKA_DATA_PATH=/kafka_data # Путь в HDFS для данных
```

### Подключение к DataProc HDFS

Так как DataProc кластер в Yandex Cloud имеет публичные IP на всех узлах, подключение возможно напрямую:

```bash
# Получить публичный IP мастер-ноды
terraform output dataproc_master_ips

# Подключение по SSH
ssh -i ~/.ssh/yandex_cloud ubuntu@<dataproc_master_public_ip>

# Then inside HDFS
hdfs dfs -ls /kafka_data
hdfs dfs -cat /kafka_data/products_batch_*
```

### Web UI для мониторинга HDFS

```bash
# NameNode Web UI
http://<dataproc_master_public_ip>:9870
```

## Скриншоты для отчета

### Задание 1 (Kafka + Schema Registry):

```bash
# Регистрация схемы
SCHEMA_URL=$(terraform output -raw schema_registry_urls | head -1)
curl -u admin:<password> -k $SCHEMA_URL/subjects

# Детали схемы
curl -X GET -u admin:<password> -k \
  $SCHEMA_URL/subjects/test-topic-value/versions/latest

# Описание топика
yc managed-kafka topic list --cluster-name kafka-cluster
```

### Задание 2 (Hadoop HDFS):

```bash
# Консоль DataProc
yc dataproc cluster list
yc dataproc cluster get <cluster-id>

# Проверка данных в HDFS (через SSH на мастер-ноду)
terraform output dataproc_master_ips
ssh -i ~/.ssh/yandex_cloud ubuntu@<dataproc_master_public_ip>

hdfs dfs -ls /kafka_data
hdfs dfs -cat /kafka_data/products_batch_*

# NameNode Web UI
# Открыть в браузере: http://<dataproc_master_public_ip>:9870

# Логи консьюмера
docker-compose logs consumer
```

## Формат данных в HDFS

CSV формат:
```csv
1,Product 1
2,Product 2
3,Product 3
...
```

Имя файла: `kafka_data/products_batch_<timestamp>.csv` в `/kafka_data/`

## Основные файлы

- `domain/product.go`: ProcessProducts() - запись в HDFS
- `infra/clients/hdfs/client.go`: Реализация HDFS клиента
- `infra/clients/kafka/consumer.go`: processPartition() - чтение из Kafka
- `interfaces/interfaces.go`: HDFSClient интерфейс

## Конфигурация Security Groups

### Kafka (infra-sg)
- 9091: Kafka SASL_SSL
- 443: Schema Registry HTTPS
- 22: SSH
- 0-65535: Внутренний трафик кластера

### DataProc (dataproc-sg)
- 8020, 9000: HDFS NameNode RPC
- 9870: HDFS NameNode Web UI
- 50010: HDFS DataNode transfer
- 50020: HDFS DataNode IPC
- 50000-51000: HDFS high ports for data transfer
- 14000-14001: HTTP FS
- 50075-50076: DataNode HTTP transfer
- 22: SSH
- 0-65535: Внутренний трафик SG
