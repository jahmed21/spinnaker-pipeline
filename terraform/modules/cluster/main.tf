# Find Project (Service).
data "google_project" "project" {
  project_id = "${var.project_id}"
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.cluster_name}-subnet"
  project                  = "${var.project_id}"
  ip_cidr_range            = "${var.subnet_range}"
  network                  = "${var.vpc_self_link}"
  private_ip_google_access = true
  enable_flow_logs         = true

  secondary_ip_range {
    range_name    = "pod-range"
    ip_cidr_range = "${var.k8s_pod_cidr}"
  }

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "${var.k8s_services_cidr}"
  }
}

resource "google_container_cluster" "cluster" {
  provider = "google-beta"
  name     = "${var.cluster_name}"
  zone     = "${var.zone}"
  project  = "${var.project_id}"

  # Deploy into VPC
  #network    = "${var.vpc_self_link}"
  #subnetwork = "${google_compute_subnetwork.subnet.self_link}"
  network    = "projects/${var.project_id}/global/networks/${var.vpc_name}"
  subnetwork = "projects/${var.project_id}/regions/${var.region}/subnetworks/${google_compute_subnetwork.subnet.name}"

  # Private GKE
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "${var.master_ipv4_cidr_block}"
  }

  min_master_version = "${var.kubernetes_version}"
  node_version       = "${var.kubernetes_version}"

  # Restrict master authorised networks
  master_authorized_networks_config {
    cidr_blocks = "${var.master_authorized_cidr_blocks}"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "${google_compute_subnetwork.subnet.secondary_ip_range.0.range_name}"
    services_secondary_range_name = "${google_compute_subnetwork.subnet.secondary_ip_range.1.range_name}"
  }

  network_policy {
    enabled = true
  }

  enable_legacy_abac = false

  addons_config {
    kubernetes_dashboard {
      disabled = true
    }

    network_policy_config {
      disabled = false
    }

    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  remove_default_node_pool = true

  node_pool = {
    name = "default-pool"
  }

  # Ensure cluster is not recreated when pool configuration changes
  lifecycle = {
    ignore_changes = ["node_pool"]
  }
}

locals {
  base_node_service_account_roles = [
    "roles/monitoring.viewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/storage.objectViewer",
  ]

  node_service_account_roles = "${concat(local.base_node_service_account_roles, var.node_service_account_roles)}"
}

resource "google_service_account" "node-service-account" {
  account_id   = "${google_container_cluster.cluster.name}-nodes"
  project      = "${var.project_id}"
  display_name = "Cluster Nodes Service Account"
}

resource "google_project_iam_member" "node-service-account" {
  count   = "${length(local.node_service_account_roles)}"
  project = "${var.project_id}"
  role    = "${element(local.node_service_account_roles, count.index)}"
  member  = "serviceAccount:${google_service_account.node-service-account.email}"
}

module "node_pool" {
  source             = "../node-pool"
  project_id         = "${var.project_id}"
  name               = "${var.cluster_name}-np"
  cluster_name       = "${google_container_cluster.cluster.name}"
  node_count         = "${var.node_count}"
  node_instance_type = "${var.node_instance_type}"
  node_disk_size_gb  = "${var.node_disk_size_gb}"
  service_account    = "${google_service_account.node-service-account.email}"
  oauth_scopes       = "${var.oauth_scopes}"
  tags               = "${var.default_node_pool_tags}"
}

module "nat_gw" {
  source           = "../nat-gw"
  nat_gw_name      = "${var.nat_gw_name}"
  region           = "${var.region}"
  vpc_network_name = "${var.vpc_name}"
}

output "service_account_email" {
  value = "${google_service_account.node-service-account.email}"
}
