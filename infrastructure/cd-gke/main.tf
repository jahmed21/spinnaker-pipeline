locals {
  project_id             = "cd-pipeline-2"
  spinnaker_gcs_sa_name  = "spinnaker-gcs-sa"
  spinnaker_gcs_key_name = "spinnaker-gcs-sa-key.json"
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

module "cd-gke" {
  source                  = "../modules/gke-cluster"
  name                    = "ea-cd-gke"
  region                  = "${var.region}"
  project_id              = "${local.project_id}"
  cluster_service_account = "${format("%s-compute@developer.gserviceaccount.com", data.google_project.this_projecct.number)}"
  node_instance_type      = "n1-standard-4"
  max_node_count          = "2"
  kubernetes_version      = "${data.google_container_engine_versions.gke_versions.latest_master_version}"
}

# Create GCS bucket to store spinnaker configuration
resource "google_storage_bucket" "spinnaker_config" {
  project       = "${local.project_id}"
  name          = "${local.project_id}-spinnaker-config"
  location      = "${var.region}"
  storage_class = "REGIONAL"
  force_destroy = "true"
}

resource "google_storage_bucket" "halyard_config" {
  project       = "${local.project_id}"
  name          = "${local.project_id}-halyard-config"
  location      = "${var.region}"
  storage_class = "REGIONAL"
  force_destroy = "true"
}

# Create service account for spinnaker storage
resource "google_service_account" "spinnaker_gcs" {
  project = "${local.project_id}"

  depends_on = [
    "google_storage_bucket.spinnaker_config",
  ]

  account_id   = "${local.spinnaker_gcs_sa_name}"
  display_name = "${local.spinnaker_gcs_sa_name}"
}

# Create service account key for spinnaker storage
resource "google_service_account_key" "spinnaker_gcs_key" {
  service_account_id = "${google_service_account.spinnaker_gcs.name}"
}

# Store service account key as bucket object
resource "google_storage_bucket_object" "spinnaker_gcs_key" {
  name         = "${local.spinnaker_gcs_key_name}"
  content      = "${base64decode(google_service_account_key.spinnaker_gcs_key.private_key)}"
  bucket       = "${google_storage_bucket.halyard_config.name}"
  content_type = "application/json"
}

# Grant spinnaker service account ObjectAdmin on spinnaker config bucket
resource "google_storage_bucket_iam_member" "spinnaker-bucket-access" {
  bucket = "${google_storage_bucket.spinnaker_config.name}"
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.spinnaker_gcs.email}"
}

# Allow Cloud Build service account to read the halyard-config bucket
resource "google_storage_bucket_iam_member" "cloudbuild-access-to-halyard-config-bucket" {
  bucket = "${google_storage_bucket.halyard_config.name}"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_project.this_projecct.number}@cloudbuild.gserviceaccount.com"
}

# Allow Cloud Build service account create workload in the cluster and create ClusterRoleBinding
resource "google_project_iam_member" "cloudbuild-access-to-pipeline-gke" {
  project = "${local.project_id}"
  role    = "roles/container.admin"
  member  = "serviceAccount:${data.google_project.this_projecct.number}@cloudbuild.gserviceaccount.com"
}
