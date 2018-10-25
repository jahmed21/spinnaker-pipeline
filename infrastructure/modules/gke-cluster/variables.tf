variable "region" {
  description = "GCP region."
}

variable "name" {
  description = "GKE name."
}

variable "project_id" {
  description = "Service Project ID."
}

variable "cluster_service_account" {
  description = "Specify a service account under which to run the cluster"
}

variable "master_ipv4_cidr_block" {
  description = "Private CIDR block for the master's VPC. The master range must not overlap with any subnet in the cluster's VPC and must be /28 subnet."
  default = "172.16.0.0/28"
}

variable "master_authorized_cidr_blocks" {
  description = "A list of CIDR blocks used with master_authorized_networks_config"
  type        = "list"
  default     = []
}

variable "maintenance_window_start_time" {
  type        = "string"
  description = "Maintenance window start time in GMT"
  default     = "15:00"  # 1am AEST
}

variable "enable_binary_authorization" {
  description = "Enable cluster binary authorization feature"
  default     = false
}

variable "initial_node_count" {
  description = "Initial number of nodes to create in the node pool.  Changing this recreates the node pool"
  default     = 1
}

variable "min_node_count" {
  description = "Autoscaling min number of nodes"
  default     = 1
}

variable "max_node_count" {
  description = "Autoscaling max number of nodes"
  default     = 1
}

variable "node_instance_type" {
  description = "GCE instance type for the default node pool"
  type        = "string"
  default     = "n1-standard-2"
}

variable "node_disk_size_gb" {
  description = "Size of the disk attached to each node, specified in GB"
  default     = 50
}

variable "kubernetes_version" {
  type    = "string"
  default = "1.10.7-gke.6"
}

variable "oauth_scopes" {
  description = "Cluster oauth scopes"
  type        = "list"
  default     = []
}
