variable "folder_id" {
  description = "Yandex Cloud Folder ID"
  type        = string
}

variable "zone" {
  description = "Yandex Cloud availability zone"
  type        = string
  default     = "ru-central1-a"
}

variable "kafka_user" {
  description = "Kafka admin username"
  type        = string
  default     = "admin"
}

variable "kafka_password" {
  description = "Kafka admin password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
}

variable "cloud_id" {
  description = "ID облака в Yandex Cloud"
  type        = string
}