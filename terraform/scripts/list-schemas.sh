#!/bin/bash
# Скрипт для проверки зарегистрированных схем (Yandex Managed Kafka)

SCHEMA_REGISTRY_URL="${1:-https://localhost:443}"
SR_USER="${2:-admin}"
SR_PASSWORD="${3:-YOUR_PASSWORD}"

echo "Список зарегистрированных subjects:"
curl -s -u "$SR_USER:$SR_PASSWORD" -k "$SCHEMA_REGISTRY_URL/subjects" | jq .

echo -e "\n\nДетали последней версии схем:"

curl -s -u "$SR_USER:$SR_PASSWORD" -k "$SCHEMA_REGISTRY_URL/subjects" | jq -r '.[] | @text' | while read subject; do
  LATEST_VERSION=$(curl -s -u "$SR_USER:$SR_PASSWORD" -k "$SCHEMA_REGISTRY_URL/subjects/$subject/versions/latest" | jq -r '.version')
  echo "$subject (версия: $LATEST_VERSION)"
  curl -s -u "$SR_USER:$SR_PASSWORD" -k "$SCHEMA_REGISTRY_URL/subjects/$subject/versions/$LATEST_VERSION" | jq '.' 
  echo "---"
done
