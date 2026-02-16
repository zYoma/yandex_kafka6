#!/bin/bash
YC_FOLDER_ID=$(terraform output -raw kafka_cluster_id 2>/dev/null) || true

if [ -z "$YC_FOLDER_ID" ]; then
  echo "Не найден ID кластера из terraform. Получаем список..."
  yc managed-kafka cluster list
else
  yc managed-kafka cluster get "$YC_FOLDER_ID"
fi

echo -e "\n\nПартиции и топики:"

# Получить топики через yc CLI если доступно
yc managed-kafka topic list --cluster-name kafka-cluster 2>/dev/null || echo "Установите yc CLI для просмотра топиков"
