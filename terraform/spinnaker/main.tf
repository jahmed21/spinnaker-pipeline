locals {
  zone                         = "asia-southeast1-b"
  project_id                   = "xanthic-1eebe7"
  spin_subnet_range            = "10.10.1.0/27"
  spin_master_ipv4_cidr_block  = "10.10.17.0/28"
  spin_k8s_services_cidr       = "10.10.18.0/24"
  spin_k8s_pod_cidr            = "10.10.160.0/19"
  app_x_subnet_range           = "10.20.1.0/27"
  app_x_master_ipv4_cidr_block = "10.20.17.0/28"
  app_x_k8s_services_cidr      = "10.20.18.0/24"
  app_x_k8s_pod_cidr           = "10.20.160.0/19"
  app_y_subnet_range           = "10.30.1.0/27"
  app_y_master_ipv4_cidr_block = "10.30.17.0/28"
  app_y_k8s_services_cidr      = "10.30.18.0/24"
  app_y_k8s_pod_cidr           = "10.30.160.0/19"
}

provider "google" {
  zone    = "${local.zone}"
  version = "~> 1.19"
}

provider "google-beta" {
  zone    = "${local.zone}"
  version = "~> 1.19"
}

resource "google_compute_network" "spin-vpc" {
  project                 = "${local.project_id}"
  name                    = "spin-vpc"
  auto_create_subnetworks = "false"
  routing_mode            = "REGIONAL"
}

resource "google_compute_network" "app-vpc" {
  project                 = "${local.project_id}"
  name                    = "app-vpc"
  auto_create_subnetworks = "false"
  routing_mode            = "REGIONAL"
}

module "spin-cluster" {
  source                 = "../modules/cluster"
  cluster_name           = "spin-cluster"
  vpc_name               = "${google_compute_network.spin-vpc.id}"
  vpc_self_link          = "${google_compute_network.spin-vpc.self_link}"
  project_id             = "${local.project_id}"
  subnet_range           = "${local.spin_subnet_range}"
  master_ipv4_cidr_block = "${local.spin_master_ipv4_cidr_block}"
  k8s_services_cidr      = "${local.spin_k8s_services_cidr}"
  k8s_pod_cidr           = "${local.spin_k8s_pod_cidr}"
  node_instance_type     = "n1-standard-2"
  node_count             = "3"
  default_node_pool_tags = ["spin-cluster-np"]
}

#module "app-x-cluster" {
#  source                 = "../modules/cluster"
#  cluster_name           = "app-x-cluster"
#  vpc_name               = "${google_compute_network.app-vpc.id}"
#  vpc_self_link          = "${google_compute_network.app-vpc.self_link}"
#  project_id             = "${local.project_id}"
#  subnet_range           = "${local.app_x_subnet_range}"
#  master_ipv4_cidr_block = "${local.app_x_master_ipv4_cidr_block}"
#  k8s_services_cidr      = "${local.app_x_k8s_services_cidr}"
#  k8s_pod_cidr           = "${local.app_x_k8s_pod_cidr}"
#  node_instance_type     = "n1-standard-1"
#  default_node_pool_tags = ["app-x-cluster-np"]
#  depends_on             = "${module.spin-cluster.id}"
#}

#module "app-y-cluster" {
#  source                 = "../modules/cluster"
#  cluster_name           = "app-y-cluster"
#  vpc_name               = "${google_compute_network.app-vpc.id}"
#  vpc_self_link          = "${google_compute_network.app-vpc.self_link}"
#  project_id             = "${local.project_id}"
#  subnet_range           = "${local.app_y_subnet_range}"
#  master_ipv4_cidr_block = "${local.app_y_master_ipv4_cidr_block}"
#  k8s_services_cidr      = "${local.app_y_k8s_services_cidr}"
#  k8s_pod_cidr           = "${local.app_y_k8s_pod_cidr}"
#  node_instance_type     = "n1-standard-1"
#  default_node_pool_tags = ["app-y-cluster-np"]
#}

resource "google_compute_network_peering" "spin-app-peering" {
  name               = "spin-app-peering"
  network            = "${google_compute_network.spin-vpc.self_link}"
  peer_network       = "${google_compute_network.app-vpc.self_link}"
  auto_create_routes = true
}

resource "google_compute_network_peering" "app-spin-peering" {
  name               = "app-spin-peering"
  network            = "${google_compute_network.app-vpc.self_link}"
  peer_network       = "${google_compute_network.spin-vpc.self_link}"
  auto_create_routes = true
}

resource "google_compute_firewall" "deny-api-proxy-ingress-from-all" {
  count = 0 # Disabled

  depends_on = [
    "google_compute_network_peering.spin-app-peering",
    "google_compute_network_peering.app-spin-peering",
  ]

  provider       = "google-beta"
  name           = "deny-api-proxy-ingress-from-all"
  description    = "Deny API and Proxy port from all subnets (expect local subnet, uses default) "
  project        = "${local.project_id}"
  network        = "${google_compute_network.app-vpc.id}"
  direction      = "INGRESS"
  enable_logging = true
  priority       = 900

  source_ranges = [
    "0.0.0.0/0",
  ]

  target_tags = [
    "app-x-cluster-np",
    "app-y-cluster-np",
  ]

  deny {
    protocol = "tcp"
    ports    = ["443", "80"]
  }
}

resource "google_compute_firewall" "allow-api-proxy-ingress-from-peering" {
  count = 0 # Disabled

  depends_on = [
    "google_compute_network_peering.spin-app-peering",
    "google_compute_network_peering.app-spin-peering",
  ]

  provider       = "google-beta"
  name           = "allow-api-proxy-ingress-from-peering"
  description    = "To allow API and Proxy ingress from peering"
  project        = "${local.project_id}"
  network        = "${google_compute_network.app-vpc.id}"
  direction      = "INGRESS"
  enable_logging = true
  priority       = 800

  source_ranges = [
    "${local.spin_k8s_pod_cidr}",
    "${local.app_x_k8s_pod_cidr}",
    "${local.app_y_k8s_pod_cidr}",
  ]

  target_tags = [
    "app-x-cluster-np",
    "app-y-cluster-np",
  ]

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }
}
