variable "region" {
  description = "GCP region."
}

variable "project_id" {
  description = "Service Project ID."
}

variable "name" {
  description = "Name of the node pool"
  default     = "default-pool"
}

variable "cluster_name" {
  description = "Name of the cluster"
}

variable "node_instance_type" {
  description = "GCE instance type for the default node pool"
  type        = "string"
  default     = "n1-standard-2"
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

variable "node_disk_size_gb" {
  description = "Size of the disk attached to each node, specified in GB"
  default     = 100
}

variable "service_account" {
  description = "The ID of the service account to run the nodes under"
  type        = "string"
}

variable "labels" {
  description = "The kubernetes labels to be applied to the node pool, to be used for selective pod scheduling"
  type        = "map"
  default     = {}
}

variable "oauth_scopes" {
  description = "Cluster oauth scopes"
  type        = "list"
  default     = []
}
