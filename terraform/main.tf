terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.100"
    }
  }
}

provider "yandex" {}

locals {
  folder_id    = var.folder_id
  zone         = var.zone
}

resource "yandex_vpc_network" "kafka_network" {
  name = "kafka-network"
}

resource "yandex_vpc_subnet" "kafka_subnet" {
  name           = "kafka-subnet"
  zone           = local.zone
  network_id     = yandex_vpc_network.kafka_network.id
  v4_cidr_blocks = ["10.0.0.0/24"]
}

resource "yandex_mdb_kafka_cluster" "kafka_cluster" {
  name        = "kafka-cluster"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.kafka_network.id

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

  zones = [local.zone]

  brokers_count = 3

  host {
    zone       = local.zone
    subnet_id  = yandex_vpc_subnet.kafka_subnet.id
    assign_public_ip = false
  }

  host {
    zone            = local.zone
    subnet_id       = yandex_vpc_subnet.kafka_subnet.id
    assign_public_ip = true
    type            = "SCHEMA_REGISTRY"
  }

  user {
    name     = var.kafka_user
    password = var.kafka_password
  }

  topic {
    name             = "test-topic"
    partitions       = 3
    replication_factor = 3
    topic_config {
      cleanup_policy = "delete"
      retention_ms   = 259200000
      segment_bytes  = 1073741824
    }
  }
}

resource "yandex_dataproc_cluster" "hadoop_cluster" {
  name        = "hadoop-cluster"
  folder_id   = local.folder_id
  description = "Hadoop HDFS для интеграции с Kafka"
  service_account_id = yandex_iam_service_account.dataproc_sa.id

  zone_id = local.zone

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

  security_group_ids = [yandex_vpc_security_group.kafka_sg.id]
}

resource "yandex_iam_service_account" "dataproc_sa" {
  name = "dataproc-service-account"
}

resource "yandex_resourcemanager_folder_iam_member" "dataproc_sa" {
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.dataproc_sa.id}"
  role      = "dataproc.agent"
}

resource "yandex_vpc_security_group" "kafka_sg" {
  name        = "kafka-security-group"
  network_id  = yandex_vpc_network.kafka_network.id

  ingress {
    protocol       = "ANY"
    description    = "Allow internal traffic"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["10.0.0.0/24"]
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    from_port      = 22
    to_port        = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "Schema Registry"
    from_port      = 443
    to_port        = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "DataProc SSH proxy"
    from_port      = 50105
    to_port        = 50105
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "Hadoop Web UI (YARN, NameNode)"
    from_port      = 8070
    to_port        = 9870
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
