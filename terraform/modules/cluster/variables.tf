variable "project_id" {}
variable "cluster_name" {}
variable "master_ipv4_cidr_block" {}
variable "k8s_services_cidr" {}
variable "subnet_range" {}
variable "k8s_pod_cidr" {}
variable "vpc_name" {}
variable "vpc_self_link" {}

variable "nat_gw_name" {
  default = ""
}

variable "zone" {
  default = "asia-east1-b"
}

variable "region" {
  default = "asia-east1"
}

variable "master_authorized_cidr_blocks" {
  type = "list"

  default = [
    {
      cidr_block = "156.13.70.0/23"
    },
    {
      cidr_block = "182.55.128.0/19"
    },
  ]
}

variable "node_count" {
  default = 2
}

variable "node_instance_type" {
  default = "n1-standard-2"
}

variable "node_disk_size_gb" {
  default = 50
}

variable "kubernetes_version" {
  default = "1.10.9-gke.5"
}

variable "oauth_scopes" {
  type    = "list"
  default = []
}

variable "node_service_account_roles" {
  type    = "list"
  default = []
}

variable "default_node_pool_tags" {
  type    = "list"
  default = []
}
