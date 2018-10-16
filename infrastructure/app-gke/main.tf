locals {
  project_id = "app-project-002"
  region     = "asia-southeast1"
}

data "google_project" "this_projecct" {
  project_id = "${local.project_id}"
}

data "google_compute_zones" "gke_zones" {
  project = "${local.project_id}"
  region  = "${local.region}"
}

data "google_container_engine_versions" "gke_versions" {
  project = "${local.project_id}"
  zone    = "${data.google_compute_zones.gke_zones.names[0]}"
}

module "app-gke" {
  source                  = "../modules/gke-cluster"
  name                    = "ea-app-gke"
  region                  = "${local.region}"
  project_id              = "${local.project_id}"
  cluster_service_account = "${format("%s-compute@developer.gserviceaccount.com", data.google_project.this_projecct.number)}"
  node_instance_type      = "n1-standard-1"
  max_node_count          = "1"
  kubernetes_version      = "1.10.6-gke.2"
}
