terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.100.0"
    }
  }
}

provider "yandex" {
  service_account_key_file = "/home/zyoma/terraform-sa-key.json"
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
} 



############################
# Locals
############################

locals {
  folder_id = var.folder_id
  zone      = var.zone
}

############################
# Network
############################

resource "yandex_vpc_network" "network" {
  name = "infra-network"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "infra-subnet"
  zone           = local.zone
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.0.0.0/24"]
}

############################
# Security Group
############################

resource "yandex_vpc_security_group" "sg" {
  name       = "infra-sg"
  network_id = yandex_vpc_network.network.id

  ingress {
    protocol       = "ANY"
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
    description    = "Kafka SSL"
    from_port      = 9091
    to_port        = 9091
    v4_cidr_blocks = ["10.0.0.0/24"]
  }

  ingress {
    protocol       = "TCP"
    description    = "Schema Registry"
    from_port      = 443
    to_port        = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

############################
# Kafka Cluster
############################

resource "yandex_mdb_kafka_cluster" "kafka_cluster" {
  name        = "kafka-cluster"
  folder_id   = local.folder_id
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.network.id

  security_group_ids = [yandex_vpc_security_group.sg.id]

  config {
    version       = "3.9"
    brokers_count = 3
    zones         = [local.zone]

    kafka {
      resources {
        resource_preset_id = "s3-c2-m8"
        disk_size          = 100
        disk_type_id       = "network-ssd"
      }

      kafka_config {
        compression_type    = "COMPRESSION_TYPE_GZIP"
        log_retention_hours = 72
      }
    }

    schema_registry = true
  }

  user {
    name     = var.kafka_user
    password = var.kafka_password
  }
}

############################
# DataProc Service Account
############################

resource "yandex_iam_service_account" "dataproc_sa" {
  name = "dataproc-sa"
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

############################
# DataProc Cluster
############################

resource "yandex_dataproc_cluster" "hadoop_cluster" {
  name        = "hadoop-cluster"
  folder_id   = var.folder_id
  description = "Hadoop HDFS для интеграции с Kafka"
  service_account_id = yandex_iam_service_account.dataproc_sa.id
  zone_id = var.zone

  cluster_config {
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
      subnet_id   = yandex_vpc_subnet.subnet.id
      assign_public_ip = true

      ssh_key = file("~/.ssh/terraform-dataproc.pub")
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
      subnet_id   = yandex_vpc_subnet.subnet.id
      assign_public_ip = false

      ssh_key = file("~/.ssh/terraform-dataproc.pub")
    }
  }

  security_group_ids = [yandex_vpc_security_group.sg.id]
}
