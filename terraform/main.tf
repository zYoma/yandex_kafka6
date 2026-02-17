terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.100"
    }
  }
}

provider "yandex" {}

########################################
# Variables
########################################

variable "folder_id" {
  type = string
}

variable "zone" {
  type    = string
  default = "ru-central1-a"
}

variable "kafka_user" {
  type = string
}

variable "kafka_password" {
  type      = string
  sensitive = true
}

########################################
# Locals
########################################

locals {
  folder_id = var.folder_id
  zone      = var.zone
}

########################################
# Network
########################################

resource "yandex_vpc_network" "kafka_network" {
  name = "kafka-network"
}

resource "yandex_vpc_subnet" "kafka_subnet" {
  name           = "kafka-subnet"
  zone           = local.zone
  network_id     = yandex_vpc_network.kafka_network.id
  v4_cidr_blocks = ["10.0.0.0/24"]
}

########################################
# Security Group
########################################

resource "yandex_vpc_security_group" "kafka_sg" {
  name       = "kafka-security-group"
  network_id = yandex_vpc_network.kafka_network.id

  # внутренний трафик
  ingress {
    protocol       = "ANY"
    description    = "Allow internal traffic"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["10.0.0.0/24"]
  }

  # Kafka SSL
  ingress {
    protocol       = "TCP"
    description    = "Kafka SSL"
    from_port      = 9091
    to_port        = 9091
    v4_cidr_blocks = ["10.0.0.0/24"]
  }

  # SSH
  ingress {
    protocol       = "TCP"
    description    = "SSH"
    from_port      = 22
    to_port        = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Schema Registry (HTTPS)
  ingress {
    protocol       = "TCP"
    description    = "Schema Registry"
    from_port      = 443
    to_port        = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

########################################
# Kafka Cluster
########################################

resource "yandex_mdb_kafka_cluster" "kafka_cluster" {
  name        = "kafka-cluster"
  folder_id   = local.folder_id
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.kafka_network.id

  security_group_ids = [
    yandex_vpc_security_group.kafka_sg.id
  ]

  kafka {
    resources {
      resource_preset_id = "s3-c2-m8"
      disk_size          = 100
      disk_type_id       = "network-ssd"
    }

    config {
      compression_type    = "gzip"
      log_retention_bytes = 1073741824
      log_retention_hours = 72
      log_segment_bytes   = 1073741824
    }
  }

  schema_registry {
    enabled = true
  }

  zones         = [local.zone]
  brokers_count = 3

  user {
    name     = var.kafka_user
    password = var.kafka_password
  }

  topic {
    name               = "test-topic"
    partitions         = 3
    replication_factor = 3

    topic_config {
      cleanup_policy = "delete"
      retention_ms   = 259200000
      segment_bytes  = 1073741824
    }
  }
}

########################################
# DataProc Service Account
########################################

resource "yandex_iam_service_account" "dataproc_sa" {
  name = "dataproc-service-account"
}

resource "yandex_resourcemanager_folder_iam_member" "dataproc_agent" {
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.dataproc_sa.id}"
  role      = "dataproc.agent"
}

resource "yandex_resourcemanager_folder_iam_member" "dataproc_provisioner" {
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.dataproc_sa.id}"
  role      = "dataproc.provisioner"
}

########################################
# DataProc Cluster
########################################

resource "yandex_dataproc_cluster" "hadoop_cluster" {
  name                = "hadoop-cluster"
  folder_id           = local.folder_id
  description         = "Hadoop HDFS для интеграции с Kafka"
  service_account_id  = yandex_iam_service_account.dataproc_sa.id
  zone_id             = local.zone
  security_group_ids  = [yandex_vpc_security_group.kafka_sg.id]

  config {
    version_id = "2.1.1"

    hadoop {
      services = ["HDFS", "ZOOKEEPER"]
    }

    subcluster_spec {
      name = "subcluster-master"
      role = "MASTERNODE"

      resources {
        resource_preset_id = "s3-c2-m8"
        disk_type_id       = "network-ssd"
        disk_size          = 100
      }

      hosts_count = 1
      subnet_id   = yandex_vpc_subnet.kafka_subnet.id
      assign_public_ip = true
    }

    subcluster_spec {
      name = "subcluster-worker"
      role = "DATANODE"

      resources {
        resource_preset_id = "s3-c2-m8"
        disk_type_id       = "network-ssd"
        disk_size          = 200
      }

      hosts_count = 2
      subnet_id   = yandex_vpc_subnet.kafka_subnet.id
      assign_public_ip = false
    }
  }
}
