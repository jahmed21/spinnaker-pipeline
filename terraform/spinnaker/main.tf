locals {
  zone       = "asia-east1-b"
  project_id = "bmt-2201-53cd0c"
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
  subnet_range           = "10.10.1.0/27"
  master_ipv4_cidr_block = "10.10.17.0/28"
  k8s_services_cidr      = "10.10.18.0/24"
  k8s_pod_cidr           = "10.10.160.0/19"
  node_instance_type     = "n1-standard-2"
}

module "app-cluster" {
  source                 = "../modules/cluster"
  cluster_name           = "app-cluster"
  project_id             = "${local.project_id}"
  subnet_range           = "10.20.1.0/27"
  master_ipv4_cidr_block = "10.20.17.0/28"
  k8s_services_cidr      = "10.20.18.0/24"
  k8s_pod_cidr           = "10.20.160.0/19"
  node_instance_type     = "n1-standard-2"
}

resource "google_compute_network_peering" "spin-app-peering" {
  name = "spin-app-peering"
  network = "${module.spin-cluster.vpc_self_link}"
  peer_network = "${module.app-cluster.vpc_self_link}"
  auto_create_routes = true
}

resource "google_compute_network_peering" "app-spin-peering" {
  name = "app-spin-peering"
  network = "${module.app-cluster.vpc_self_link}"
  peer_network = "${module.spin-cluster.vpc_self_link}"
  auto_create_routes = true
}
