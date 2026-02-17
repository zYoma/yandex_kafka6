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

resource "yandex_vpc_gateway" "nat_gateway" {
  folder_id = var.folder_id
  name      = "nat-gateway"

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "nat_route_table" {
  folder_id  = var.folder_id
  network_id = yandex_vpc_network.network.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "infra-subnet"
  zone           = local.zone
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.0.0.0/24"]
  route_table_id = yandex_vpc_route_table.nat_route_table.id
}

############################
# Security Group
############################

resource "yandex_vpc_security_group" "sg" {
  name       = "infra-sg"
  network_id = yandex_vpc_network.network.id

  # Kafka
ingress {
  description    = "Kafka SASL_SSL"
  protocol       = "TCP"
  from_port      = 9091
  to_port        = 9091
  v4_cidr_blocks = ["0.0.0.0/0"]  # лучше ограничить своим IP
}

# Schema Registry
ingress {
  description    = "Schema Registry HTTPS"
  protocol       = "TCP"
  from_port      = 443
  to_port        = 443
  v4_cidr_blocks = ["0.0.0.0/0"]  # лучше ограничить своим IP
}
  # внутренний трафик между узлами кластера
  ingress {
    description    = "Allow internal cluster traffic"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = [yandex_vpc_subnet.subnet.v4_cidr_blocks[0]]
  }

  # SSH извне (опционально)
  ingress {
    description    = "SSH"
    protocol       = "TCP"
    from_port      = 22
    to_port        = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Исходящий трафик разрешаем весь
  egress {
    description    = "Allow all outbound"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG для DataProc
resource "yandex_vpc_security_group" "dataproc_sg" {
  name       = "dataproc-sg"
  network_id = yandex_vpc_network.network.id
}

# Ingress: весь трафик между членами SG
resource "yandex_vpc_security_group_rule" "dataproc_internal_ingress" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow all internal traffic within the SG"

  from_port         = 0
  to_port           = 65535
  protocol          = "ANY"
  predefined_target = "self_security_group"
}

# Egress: весь трафик между членами SG
resource "yandex_vpc_security_group_rule" "dataproc_internal_egress" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "egress"
  description            = "Allow all internal traffic within the SG"

  from_port         = 0
  to_port           = 65535
  protocol          = "ANY"
  predefined_target = "self_security_group"
}

# Дополнительно: весь трафик внутри подсети (например, к хранилищу)
resource "yandex_vpc_security_group_rule" "dataproc_subnet_internal" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow internal traffic to subnet resources (HDFS, storage, etc.)"

  from_port      = 0
  to_port        = 65535
  protocol       = "ANY"
  v4_cidr_blocks = [yandex_vpc_subnet.subnet.v4_cidr_blocks[0]]
}

# Egress: весь трафик в интернет (обновления, доступ к S3, etc.)
resource "yandex_vpc_security_group_rule" "dataproc_egress_all" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "egress"
  description            = "Allow all outbound traffic"

  from_port      = 0
  to_port        = 65535
  protocol       = "ANY"
  v4_cidr_blocks = ["0.0.0.0/0"]
}


############################
# Kafka Cluster
############################

resource "yandex_mdb_kafka_cluster" "kafka_cluster" {
  name        = "kafka-cluster"
  folder_id   = local.folder_id
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.network.id
  subnet_ids  = [yandex_vpc_subnet.subnet.id] 

  security_group_ids = [yandex_vpc_security_group.sg.id]

  config {
    version       = "3.9"
    brokers_count = 3
    zones         = [local.zone]
    assign_public_ip = true

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
    permission {
      topic_name = "*"
      role       = "ACCESS_ROLE_ADMIN"
  }
  }
}

resource "yandex_mdb_kafka_topic" "test_topic" {
  name          = "test-topic"
  cluster_id    = yandex_mdb_kafka_cluster.kafka_cluster.id
  partitions    = 3
  replication_factor = 3

  retention {
    size   = 100000000  # в байтах
    period = "72h"
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
  security_group_ids = [yandex_vpc_security_group.dataproc_sg.id]

  cluster_config {
    version_id = "2.1"

    hadoop {
      services = ["HDFS"]
      ssh_public_keys = [
        file("~/.ssh/terraform-dataproc.pub")
      ]
    }

    subcluster_spec {
      name = "subcluster-master"
      role = "MASTERNODE"

      resources {
        resource_preset_id = "s3-c2-m8"
        disk_type_id       = "network-ssd"
        disk_size          = 50
      }

      hosts_count = 1
      subnet_id   = yandex_vpc_subnet.subnet.id
      assign_public_ip = true


    }

    subcluster_spec {
      name = "subcluster-worker"
      role = "DATANODE"

      resources {
        resource_preset_id = "s3-c2-m8"
        disk_type_id       = "network-ssd"
        disk_size          = 50
      }

      hosts_count = 2
      subnet_id   = yandex_vpc_subnet.subnet.id
      assign_public_ip = false


    }
  }


}
