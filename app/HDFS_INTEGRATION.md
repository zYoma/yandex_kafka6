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
cd /Users/user/GoProjects/yandex_kafka_6
terraform init
terraform apply
```

### 2. Получить параметры

```bash
# Kafka bootstrap servers
terraform output kafka_bootstrap_servers

# Schema Registry URL
terraform output schema_registry_url

# DataProc кластера
terraform output dataproc_cluster_id
```

### 3. Скачать CA сертификат

Консоль Yandex -> Managed Service for Apache Kafka -> Сертификаты -> Скачать
Сохранить как `app/certs/CACerts.pem`

### 4. Настроить .env

```bash
cd app
cp .env.example .env
# Отредактировать:
# BOOTSTRAP_SERVER=<хосты_кафка>
# SCHEMA_REGISTRY_SERVICE_URL=https://<schema_registry_host>
# SASL_PASSWORD=<ваш_пароль>
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
HADOOP_HDFS_MODE=false          # true - использовать настоящий HDFS
HDFS_ADDRESSES=namenode:9000    # Адрес NameNode (для локального тестирования)
HDFS_KAFKA_DATA_PATH=/kafka_data # Путь в HDFS для данных
DATAPROC_MASTER_HOST=           # Хост DataProc (если доступен)
```

### Для реального подключения к DataProc HDFS:

Так как DataProc кластер в Yandex Cloud не имеет публичного NameNode, используйте:

#### Вариант 1: Через SSH туннель (из консьюмера на VM)
```bash
# На VM запустить SSH tunnel к DataProc
ssh -i ~/.ssh/yandex_cloud -L 9000:<namenode_internal>:8020 \
  ubuntu@<dataproc_master_public_ip>

# В HDFS_ADDRESSES указать localhost:9000
```

#### Вариант 2: Через yc dataproc ssh (ручная проверка)
```bash
yc dataproc ssh <cluster-id> --host <hostname> --ssh-key ~/.ssh/yandex_cloud

# Then inside HDFS
hdfs dfs -ls /kafka_data
hdfs dfs -cat /kafka_data/products_batch_*
```

## Скриншоты для отчета

### Задание 1 (Kafka + Schema Registry):

```bash
# Регистрация схемы
curl -u admin:<password> -k https://<schema_registry_url>/subjects

# Детали схемы
curl -X GET -u admin:<password> -k \
  https://<schema_registry_url>/subjects/test-topic-value/versions/latest

# Описание топика
yc managed-kafka topic list --cluster-name kafka-cluster
```

### Задание 2 (Hadoop HDFS):

```bash
# Консоль DataProc
yc dataproc cluster list
yc dataproc cluster get <cluster-id>

# Проверка данных в HDFS (через SSH на мастер-ноду)
yc dataproc ssh <cluster-id> --host <namenode> --ssh-key ~/.ssh/yandex_cloud

hdfs dfs -ls /kafka_data
hdfs dfs -cat /kafka_data/products_batch_*

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
