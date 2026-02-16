output "kafka_cluster_id" {
  description = "Kafka cluster ID"
  value       = yandex_mdb_kafka_cluster.kafka_cluster.id
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers"
  value       = join(",", [for h in yandex_mdb_kafka_cluster.kafka_cluster.host: "${h.name}:9091" if h.type == "KAFKA"])
}

output "schema_registry_url" {
  description = "Schema Registry URL"
  value       = "https://${[for h in yandex_mdb_kafka_cluster.kafka_cluster.host: h if h.type == "SCHEMA_REGISTRY"][0].name}:443"
}

output "dataproc_cluster_id" {
  description = "DataProc cluster ID"
  value       = yandex_dataproc_cluster.hadoop_cluster.id
}

output "dataproc_master_ip" {
  description = "DataProc master public IP"
  value       = [for h in yandex_dataproc_cluster.hadoop_cluster.host[0]: h if h.subcluster_role == "MASTERNODE"][0].assign_public_ip
}

output "hadoop_web_ui" {
  description = "Hadoop Web UI URL"
  value       = "http://${[for h in yandex_dataproc_cluster.hadoop_cluster.host: h if h.subcluster_role == "MASTERNODE"][0].name}:8088"
}
