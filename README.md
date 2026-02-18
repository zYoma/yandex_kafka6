# Yandex Cloud Kafka + Hadoop Deployment

## Подготовка

```bash
# Создать сервисный аккаунт и получить OAuth токен
yc init

# Получить ID папки
yc resource-manager folder list

# Создать SSH ключи (если нет)
ssh-keygen -t rsa -f ~/.ssh/yandex_cloud -N ""
```

## Переменные

Создать файл `terraform/terraform.tfvars`:
```hcl
cloud_id            = "ваш_cloud_id"
folder_id           = "ваш_folder_id"
zone                = "ru-central1-a"
kafka_password      = "сложный_пароль"
ssh_public_key_path = "~/.ssh/yandex_cloud.pub"
```

## Развертывание

```bash
cd terraform
terraform init
terraform apply
```

**Внимание:** DataProc кластер создается 10-15 минут

## Доступ после развертывания

Получить IP адреса и URL:
```bash
terraform output
```

## Выводы Terraform

- **kafka_cluster_id**: ID кластера Kafka
- **kafka_hosts**: Список хостов Kafka (FQDN)
- **kafka_public_hosts**: Хосты Kafka с публичными IP
- **schema_registry_urls**: URL Schema Registry (HTTPS на порту 443)
- **dataproc_cluster_id**: ID кластера DataProc
- **dataproc_master_ips**: Публичные IP мастер-нод DataProc

## Schema Registry (встроенный в Yandex Managed Kafka)

Проверка доступа:
```bash
# Используйте учетные данные admin / ваш_пароль
curl -u admin:пароль -k https://<schema_registry_host>:443/subjects
```

Регистрация схемы:
```bash
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -u admin:пароль -k \
  --data @terrafrom/schemas/product.avsc \
  https://<schema_registry_host>:443/subjects/product-value/versions
```

Проверка схемы:
```bash
curl -X GET -u admin:пароль -k \
  https://<schema_registry_host>:443/subjects/test-topic-value/versions/latest
```

## Hadoop Web UI (Yandex Data Processing)

```bash
# NameNode Web UI
http://<dataproc_master_public_ip>:9870
```

## Подключение к DataProc кластеру

Для подключения к DataProc используйте публичный IP (все узлы имеют публичные IP):

```bash
# Получить публичный IP мастер-ноды
terraform output dataproc_master_ips

# Подключение по SSH
ssh -i ~/.ssh/yandex_cloud ubuntu@<dataproc_master_public_ip>

# Или используйте yc dataproc connect
yc dataproc connect <cluster-id> --host <hostname> --ssh-key ~/.ssh/yandex_cloud
```

## Kafka подключения

Получить строку подключения:
```bash
terraform output kafka_hosts
```

Учетные данные:
- Пользователь: admin
- Пароль: указан в terraform.tfvars
- Протокол: SASL_SSL
- Механизм: SCRAM-SHA-512
- Порт: 9091

CA сертификат для SSL (скачать из консоли Yandex):
Консоль -> Managed Service for Apache Kafka -> ваш кластер -> Certificates

## Создать топик (если нужно другой)
```bash
kafka-topics.sh --create \
  --bootstrap-server <kafka_hosts>:9091 \
  --command-config /path/to/client.properties \
  --topic new-topic \
  --partitions 3 \
  --replication-factor 3
```

## HDFS команды (для задания 2)

После подключения к DataProc кластеру:
```bash
# Создать директорию
hdfs dfs -mkdir /kafka_data

# Загрузить данные
hdfs dfs -put /path/to/local/file /kafka_data/

# Прочитать данные
hdfs dfs -cat /kafka_data/file
```

## Запуск продюсера и консьюмера

1. **Скачать CA сертификат:**
   Консоль -> Managed Service for Apache Kafka -> Certificates -> Скачать
   Сохранить как `app/certs/CACerts.pem`

2. **Настроить .env:**
    ```bash
    cd app
    cp .env.example .env
    # Отредактируйте BOOTSTRAP_SERVER, SCHEMA_REGISTRY_SERVICE_URL, SASL_PASSWORD, HDFS_ADDRESSES
    ```

3. **Запустить продюсер:**
    ```bash
    docker-compose up producer
    # или локально:
    go run cmd/producer/main.go
    ```

4. **Запустить консьюмер:**
    ```bash
    docker-compose up consumer
    # или локально:
    go run cmd/consumer/main.go
    ```

## Schema Registry

Схема для Product автоматически регистрируется при запуске продюсера.
Subject: `test-topic-value`

Проверка:
```bash
curl -u admin:<password> -k https://<schema_registry_url>:443/subjects
```

## Инфраструктура

### Network
- **VPC**: infra-network
- **Subnet**: 10.0.0.0/24
- **NAT Gateway**: nat-gateway для доступа в интернет
- **Route Table**: Маршрутизация через NAT

### Kafka Cluster
- **Версия**: 3.9 (PRESTABLE)
- **Брокеры**: 3 узла (s3-c2-m8: 2 CPU, 8 GB RAM)
- **Диск**: 100 GB network-ssd на брокер
- **Schema Registry**: включен
- **Публичный IP**: да
- **Порты**: 9091 (SASL_SSL), 443 (Schema Registry HTTPS)

### DataProc Cluster
- **Версия**: 2.1
- **MASTERNODE**: 1 узел (s3-c2-m8, 50 GB)
- **DATANODE**: 2 узла (s3-c2-m8, 50 GB)
- **Сервисы**: HDFS
- **Публичный IP**: да на всех узлах
- **Порты HDFS**:
  - NameNode RPC: 8020, 9000
  - DataNode transfer: 50010
  - DataNode IPC: 50020
  - WebHDFS: 9870
  - High ports: 50000-51000
  - HTTP FS: 14000-14001
  - DataNode HTTP transfer: 50075-50076

### Security Groups
- **infra-sg**: Kafka (9091, 443), SSH (22), внутренний трафик
- **dataproc-sg**: HDFS порты, SSH (22), внутренний трафик
