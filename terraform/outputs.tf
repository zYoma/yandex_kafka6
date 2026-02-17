output "kafka_cluster_id" {
  description = "Kafka cluster ID"
  value       = yandex_mdb_kafka_cluster.kafka_cluster.id
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers"
  value       = join(",", [
    for b in yandex_mdb_kafka_cluster.kafka_cluster.config[0].kafka[0].brokers : "${b.hostname}:9091"
  ])
}

output "schema_registry_url" {
  description = "Schema Registry URL"
  value       = "https://${yandex_mdb_kafka_cluster.kafka_cluster.config[0].schema_registry[0].external_endpoint}"
}

output "dataproc_cluster_id" {
  description = "DataProc cluster ID"
  value       = yandex_dataproc_cluster.hadoop_cluster.id
}

output "dataproc_master_ip" {
  description = "DataProc master public IP"
  value = yandex_dataproc_cluster.hadoop_cluster.cluster_config[0].subcluster_spec[0].hosts[0].assign_public_ip
}

output "hadoop_web_ui" {
  description = "Hadoop Web UI URL"
  value       = "http://${yandex_dataproc_cluster.hadoop_cluster.cluster_config[0].subcluster_spec[0].hosts[0].hostname}:8088"
}
