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

## Schema Registry (встроенный в Yandex Managed Kafka)

Проверка доступа:
```bash
# Используйте учетные данные admin / ваш_пароль
curl -u admin:пароль -k https://<schema_registry_host>/subjects
```

Регистрация схемы:
```bash
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -u admin:пароль -k \
  --data @terraform/schemas/product.avsc \
  https://<schema_registry_host>/subjects/product-value/versions
```

Проверка схемы:
```bash
curl -X GET -u admin:пароль -k \
  https://<schema_registry_host>/subjects/product-value/versions/latest
```

## Hadoop Web UI (Yandex Data Processing)

```bash
# YARN ResourceManager
http://<dataproc_master_public_ip>:8088

# NameNode Web UI
http://<dataproc_master_public_ip>:9870
```

## Подключение к DataProc кластеру

Для подключения к DataProc используйте SSH proxy через порт 50105:

```bash
# Получить публичный IP мастер-ноды
yc dataproc cluster get <cluster_id> --format json | jq -r '.host[0] | select(.subcluster_role=="MASTERNODE") | .assign_public_ip'

# Подключение через прокси (после получения публичного IP)
ssh -o ProxyCommand="nc -X connect -x <dataproc_master_public_ip>:50105 %h %p" \
  -i ~/.ssh/yandex_cloud \
  ubuntu@<hostname>

# Или используйте yc dataproc connect
yc dataproc connect <cluster-id> --host <hostname> --ssh-key ~/.ssh/yandex_cloud
```

## Kafka подключения

Получить строку подключения:
```bash
terraform output kafka_bootstrap_servers
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
   # Отредактируйте BOOTSTRAP_SERVER, SCHEMA_REGISTRY_SERVICE_URL, SASL_PASSWORD
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
curl -u admin:<password> -k https://<schema_registry_url>/subjects
```
