locals {
  spinnaker_gcs_sa_name  = "spinnaker-gcs-sa"
  spinnaker_gcs_key_name = "spinnaker-gcs-access-key.json"
  region                 = "asia-southeast1"
}

data "google_project" "this_projecct" {
  project_id = "${local.project_id}"
}

# Create GCS bucket to store spinnaker configuration
resource "google_storage_bucket" "spinnaker_config" {
  project       = "${local.project_id}"
  name          = "${local.project_id}-spinnaker-config"
  location      = "${local.region}"
  storage_class = "REGIONAL"
  force_destroy = "true"
}

resource "google_storage_bucket" "halyard_config" {
  project       = "${local.project_id}"
  name          = "${local.project_id}-halyard-config"
  location      = "${local.region}"
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
  depends_on = [
    "google_service_account.spinnaker_gcs",
  ]

  service_account_id = "${google_service_account.spinnaker_gcs.name}"
}

# Store service account key as bucket object
resource "google_storage_bucket_object" "spinnaker_gcs_key_store" {
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

resource "google_storage_bucket" "app-config" {
  project       = "${local.project_id}"
  name          = "${local.project_id}-app-config"
  location      = "${local.region}"
  storage_class = "REGIONAL"
  force_destroy = "true"
}

# Allow Cloud Build service account to read the halyard-config bucket
resource "google_storage_bucket_iam_member" "cloudbuild-access-to-app-config-bucket" {
  bucket = "${google_storage_bucket.app-config.name}"
  role   = "roles/storage.admin"
  member = "serviceAccount:${data.google_project.this_projecct.number}@cloudbuild.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "spinnaker-check-images-asia" {
  bucket = "asia.artifacts.${local.project_id}.appspot.com"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.spinnaker_gcs.email}"
}

# Allow spinnaker SA to have browser role on LaunchPad project (where images are stored)
# Project browser role is required to list images in the repository
# Refer https://github.com/spinnaker/spinnaker/issues/2407
resource "google_project_iam_member" "spinnaker-browse-artifacts" {
  role    = "roles/browser"
  project = "${local.project_id}"
  member  = "serviceAccount:${google_service_account.spinnaker_gcs.email}"
}

resource "google_project_iam_member" "spinnaker-csr-reader" {
  role    = "roles/source.writer"
  project = "${local.project_id}"
  member  = "serviceAccount:${google_service_account.spinnaker_gcs.email}"
}
