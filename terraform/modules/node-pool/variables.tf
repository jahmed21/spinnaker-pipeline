variable "project_id" {}
variable "cluster_name" {}
variable "name" {}
variable "service_account" {}

variable "zone" {
  default = "asia-east1-b"
}

variable "node_instance_type" {
  default = "n1-standard-2"
}

variable "node_count" {
  default = 2
}

variable "node_disk_size_gb" {
  default = 50
}

variable "labels" {
  type    = "map"
  default = {}
}

variable "oauth_scopes" {
  type    = "list"
  default = []
}

variable "tags" {
  type    = "list"
  default = []
}
