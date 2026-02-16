#!/bin/bash
# Скрипт для регистрации схемы в Schema Registry (Yandex Managed Kafka)

SCHEMA_REGISTRY_URL="${1:-https://localhost:443}"
SCHEMA_FILE="${2:-./schemas/product.avsc}"
SUBJECT_NAME="${3:-product-value}"
SR_USER="${4:-admin}"
SR_PASSWORD="${5:-YOUR_PASSWORD}"

echo "Регистрация схемы в Schema Registry..."
echo "URL: $SCHEMA_REGISTRY_URL"
echo "Файл схемы: $SCHEMA_FILE"
echo "Имя subject: $SUBJECT_NAME"
echo "Пользователь: $SR_USER"

if [ ! -f "$SCHEMA_FILE" ]; then
  echo "Ошибка: Файл схемы не найден: $SCHEMA_FILE"
  exit 1
fi

RESULT=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -u "$SR_USER:$SR_PASSWORD" -k \
  --data @"$SCHEMA_FILE" \
  "$SCHEMA_REGISTRY_URL/subjects/$SUBJECT_NAME/versions")

HTTP_CODE=$(echo "$RESULT" | tail -n1)
BODY=$(echo "$RESULT" | head -n-1)

echo "HTTP код: $HTTP_CODE"
echo "Ответ: $BODY"

if [ "$HTTP_CODE" = "200" ]; then
  echo "Регистрация успешна!"
  exit 0
else
  echo "Ошибка регистрации!"
  exit 1
fi
