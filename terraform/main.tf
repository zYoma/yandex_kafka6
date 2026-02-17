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

resource "yandex_vpc_security_group_rule" "allow_hdfs_from_my_ip" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow HDFS RPC port 8020 from my IP"

  port           = 8020
  protocol       = "TCP"
  v4_cidr_blocks = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "allow_hdfs_9000" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow HDFS NameNode RPC port 9000"

  port           = 9000
  protocol       = "TCP"
  v4_cidr_blocks = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "allow_hdfs_datanode" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow HDFS DataNode transfer port"

  port           = 50010
  protocol       = "TCP"
  v4_cidr_blocks = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "allow_hdfs_datanode_ipc" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow HDFS DataNode IPC"

  port           = 50020
  protocol       = "TCP"
  v4_cidr_blocks = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "allow_hdfs_highports" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow HDFS high ports for data transfer"

  from_port      = 50000
  to_port        = 51000
  protocol       = "TCP"
  v4_cidr_blocks = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "allow_webhdfs" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow WebHDFS HTTP"

  port           = 9870
  protocol       = "TCP"
  v4_cidr_blocks = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "allow_data_transfer_http" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow DataNode HTTP transfer"

  from_port      = 50075
  to_port        = 50076
  protocol       = "TCP"
  v4_cidr_blocks = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "allow_ssh_from_my_ip" {
  security_group_binding = yandex_vpc_security_group.dataproc_sg.id
  direction              = "ingress"
  description            = "Allow SSH from my IP"

  port           = 22
  protocol       = "TCP"
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
  cluster_id         = yandex_mdb_kafka_cluster.kafka_cluster.id
  name               = "test-topic"
  partitions         = 3
  replication_factor = 3

  topic_config {
    cleanup_policy       = "CLEANUP_POLICY_DELETE"
    compression_type     = "COMPRESSION_TYPE_LZ4"
    retention_ms         = 604800000          # время хранения
    retention_bytes      = 10737418240        # размер хранения
    max_message_bytes    = 1048588
    flush_messages       = 128
    flush_ms             = 1000
    min_insync_replicas  = 1
    segment_bytes        = 268435456
    delete_retention_ms  = 86400000
    file_delete_delay_ms = 60000
    min_compaction_lag_ms = 0
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
      properties = {
        "hdfs:dfs.namenode.kerberos.principal"      = ""
        "hdfs:dfs.data.transfer.protection"         = "authentication"
        "hdfs:hadoop.security.authentication"       = "simple"
        "hdfs:hadoop.security.authorization"        = "false"
        "hdfs:dfs.webhdfs.enabled"                  = "true"
        "hdfs:dfs.namenode.http-address"            = "0.0.0.0:9870"
        "hdfs:dfs.webhdfs.user.provider.user.pattern" = "^[A-Za-z_][A-Za-z0-9_-]*[$]?$"
      }
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
      assign_public_ip = true


    }
  }


}
