locals {
  project_id = "ea-paas"
}

data "google_project" "this_projecct" {
  project_id = "${local.project_id}"
}

data "google_compute_zones" "gke_zones" {
  project = "${local.project_id}"
  region  = "${var.region}"
}

data "google_container_engine_versions" "gke_versions" {
  project = "${local.project_id}"
  zone    = "${data.google_compute_zones.gke_zones.names[0]}"
}

module "app-gke" {
  source                  = "../modules/gke-cluster"
  name                    = "ea-app-gke"
  region                  = "${var.region}"
  project_id              = "${local.project_id}"
  cluster_service_account = "${format("%s-compute@developer.gserviceaccount.com", data.google_project.this_projecct.number)}"
  node_instance_type      = "n1-standard-2"
  max_node_count          = "2"
  kubernetes_version      = "${data.google_container_engine_versions.gke_versions.latest_master_version}"
}
