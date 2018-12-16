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
  default = "asia-southeast1-b"
}

variable "region" {
  default = "asia-southeast1"
}

variable "master_authorized_cidr_blocks" {
  type = "list"

  default = [
    # Cloud build CIDR Range use for Cloud Build to talk to MASTER GKE on public ephemeral ip address
    { cidr_block = "35.208.0.0/12" },
    { cidr_block = "35.224.0.0/12" },
    { cidr_block = "35.240.0.0/13" },
    { cidr_block = "35.192.0.0/12" },
    { cidr_block = "35.184.0.0/13" },
    { cidr_block = "104.196.0.0/14" },
    { cidr_block = "156.13.70.0/23" },
    { cidr_block = "182.55.128.0/19" },
    { cidr_block = "10.10.1.0/27" },
    { cidr_block = "10.20.1.0/27" },
    { cidr_block = "10.30.1.0/27" },
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
  default = "1.11.2-gke.18"
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

variable "depends_on" {
  default = "na"
}