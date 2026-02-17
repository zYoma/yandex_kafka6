output "kafka_cluster_id" {
  description = "Kafka cluster ID"
  value       = yandex_mdb_kafka_cluster.kafka_cluster.id
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers (internal)"
  value       = yandex_mdb_kafka_cluster.kafka_cluster.config[0].kafka[0].internal_endpoint
}

output "kafka_external_bootstrap_servers" {
  description = "Kafka bootstrap servers (external/public)"
  value       = yandex_mdb_kafka_cluster.kafka_cluster.config[0].kafka[0].external_endpoint
}

output "schema_registry_url" {
  description = "Schema Registry URL"
  value       = yandex_mdb_kafka_cluster.kafka_cluster.config[0].schema_registry_endpoint
}

output "dataproc_cluster_id" {
  description = "DataProc cluster ID"
  value       = yandex_dataproc_cluster.hadoop_cluster.id
}

output "dataproc_master_public_ip" {
  description = "DataProc master public IP"
  value       = yandex_dataproc_cluster.hadoop_cluster.master_external_ip
}

output "hadoop_web_ui" {
  description = "Hadoop Web UI URL"
  value       = "http://${yandex_dataproc_cluster.hadoop_cluster.master_external_ip}:8088"
}
