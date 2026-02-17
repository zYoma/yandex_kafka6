output "kafka_cluster_id" {
  description = "Kafka cluster ID"
  value       = yandex_mdb_kafka_cluster.kafka_cluster.id
}

output "kafka_hosts" {
  description = "List of Kafka hosts (FQDN)"
  value = [
    for h in yandex_mdb_kafka_cluster.kafka_cluster.host : h.name
  ]
}

output "kafka_public_hosts" {
  description = "Kafka hosts with public IP"
  value = [
    for h in yandex_mdb_kafka_cluster.kafka_cluster.host : h.name
    if h.assign_public_ip
  ]
}

output "schema_registry_urls" {
  description = "Schema Registry URLs (HTTPS on 443)"
  value = [
    for h in yandex_mdb_kafka_cluster.kafka_cluster.host :
    "https://${h.name}:443"
  ]
}

output "dataproc_cluster_id" {
  description = "DataProc cluster ID"
  value       = yandex_dataproc_cluster.hadoop_cluster.id
}
