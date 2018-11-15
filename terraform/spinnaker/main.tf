locals {
  zone                        = "asia-east1-b"
  project_id                  = "bmt-2201-53cd0c"
  spin_subnet_range           = "10.10.1.0/27"
  spin_master_ipv4_cidr_block = "10.10.17.0/28"
  spin_k8s_services_cidr      = "10.10.18.0/24"
  spin_k8s_pod_cidr           = "10.10.160.0/19"
  app_subnet_range            = "10.20.1.0/27"
  app_master_ipv4_cidr_block  = "10.20.17.0/28"
  app_k8s_services_cidr       = "10.20.18.0/24"
  app_k8s_pod_cidr            = "10.20.160.0/19"
}

provider "google" {
  zone    = "${local.zone}"
  version = "~> 1.19"
}

provider "google-beta" {
  zone    = "${local.zone}"
  version = "~> 1.19"
}

module "spin-cluster" {
  source                 = "../modules/cluster"
  cluster_name           = "spin-cluster"
  project_id             = "${local.project_id}"
  subnet_range           = "${local.spin_subnet_range}"
  master_ipv4_cidr_block = "${local.spin_master_ipv4_cidr_block}"
  k8s_services_cidr      = "${local.spin_k8s_services_cidr}"
  k8s_pod_cidr           = "${local.spin_k8s_pod_cidr}"
  node_instance_type     = "n1-standard-2"
  default_node_pool_tags = ["spin-cluster-np"]
}

module "app-cluster" {
  source                 = "../modules/cluster"
  cluster_name           = "app-cluster"
  project_id             = "${local.project_id}"
  subnet_range           = "${local.app_subnet_range}"
  master_ipv4_cidr_block = "${local.app_master_ipv4_cidr_block}"
  k8s_services_cidr      = "${local.app_k8s_services_cidr}"
  k8s_pod_cidr           = "${local.app_k8s_pod_cidr}"
  node_instance_type     = "n1-standard-2"
  default_node_pool_tags = ["app-cluster-np"]
}

resource "google_compute_network_peering" "spin-app-peering" {
  name               = "spin-app-peering"
  network            = "${module.spin-cluster.vpc_self_link}"
  peer_network       = "${module.app-cluster.vpc_self_link}"
  auto_create_routes = true
}

resource "google_compute_network_peering" "app-spin-peering" {
  name               = "app-spin-peering"
  network            = "${module.app-cluster.vpc_self_link}"
  peer_network       = "${module.spin-cluster.vpc_self_link}"
  auto_create_routes = true
}

resource "google_compute_firewall" "allow-k8s-api-proxy" {
  name           = "allow-k8s-api-proxy"
  description    = "To allow access to k8s-api-proxy from spin-cluster"
  project        = "${local.project_id}"
  network        = "app-cluster-vpc"
  direction      = "INGRESS"
  enable_logging = true
  priority       = 1000

  source_tags = [
    "spin-cluster-np",
  ]

  target_tags = [
    "app-cluster-np",
  ]

  allow {
    protocol = "tcp"

    ports = [
      "8118",
    ]
  }
}
