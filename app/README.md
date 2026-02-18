# Yandex Cloud Kafka + Hadoop Integration

## Быстрый старт

1. **Развернуть инфраструктуру:**
   ```bash
  terraform init
   terraform apply
   ```

2. **Получить параметры подключения:**
   ```bash
   # Kafka bootstrap servers
   terraform output kafka_bootstrap_servers

   # Schema Registry URL
   terraform output schema_registry_url
   ```

3. **Скачать CA сертификат:**
   - Консоль Yandex -> Managed Service for Apache Kafka -> Ваш кластер -> Certificates
   - Сохраните файл как `CACerts.pem` в `app/certs/`

4. **Настроить environment:**
   ```bash
   cd app
   cp .env.example .env
   # Отредактируйте .env с вашими значениями
   ```

5. **Запуск продюсера:**
   ```bash
   docker-compose up producer
   # или локально:
   go run cmd/producer/main.go
   ```

6. **Запуск консьюмера:**
   ```bash
   docker-compose up consumer
   # или локально:
   go run cmd/consumer/main.go
   ```

## Подключение к DataProc (Hadoop HDFS)

```bash
# Получить публичный IP мастер-ноды
yc dataproc cluster get <cluster-id>

# Подключиться через SSH proxy
yc dataproc ssh <cluster-id> --host <hostname> --ssh-key ~/.ssh/yandex_cloud

# HDFS команды
hdfs dfs -ls /
hdfs dfs mkdir /kafka_data
hdfs dfs -ls /kafka_data
```

## Schema Registry

Проверка схем:
```bash
curl -u admin:<password> -k https://<schema_registry_url>/subjects
```

## Структура результата для курса

```
/
|-- schemas/
|   |-- product.avsc         # JSON схема в Schema Registry (автоматически)
|-- scripts/
|   |-- register-schema.sh   # Скрипт регистрации схемы вручную
|-- app/
|   |-- producer.go          # Продюсер с поддержкой Schema Registry
|   |-- consumer.go          # Консьюмер с пакетной обработкой
|   |-- .env.example         # Пример конфигурации
|   |-- certs/
|       |-- CACerts.pem      # CA сертификат от Yandex
|-- main.tf                  # Terraform: Kafka (Managed) + DataProc
|-- README.md                # Этот файл
|-- TASKS.md                 # Задания курса
```

## Задание 1: Schema Registry

Продюсер и консьюмер используют JSON Schema автоматически:
- Продюсер регистрирует схему при запуске
- Консьюмер валидирует сообщения
- Subject: `<topic>-value`

## Задание 2: Интеграция с Hadoop HDFS

Консьюмер обрабатывает пакеты сообщений и логирует результат.

Для интеграции с Hadoop HDFS в реальном продакшене:
1. Подключитесь к DataProc кластеру через SSH
2. Запустите консьюмер - он будет читать из Kafka
3. Напишите логику отправки данных в HDFS (смотри `domain/product.go`)
4. Проверьте результат: `hdfs dfs -ls /kafka_data`
