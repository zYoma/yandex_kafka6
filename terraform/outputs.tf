output "kafka_cluster_id" {
  value = yandex_mdb_kafka_cluster.kafka_cluster.id
}

output "kafka_bootstrap_servers" {
  value = yandex_mdb_kafka_cluster.kafka_cluster.endpoints[0]
}

output "schema_registry_url" {
  value = yandex_mdb_kafka_cluster.kafka_cluster.schema_registry[0].endpoint
}

output "dataproc_cluster_id" {
  value = yandex_dataproc_cluster.hadoop_cluster.id
}
