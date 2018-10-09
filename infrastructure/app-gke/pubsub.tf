variable "pipeline_project_id" {
  default = "cd-pipeline-2"
}

variable "pipeline_project_number" {
  default = "273558596339"
}

variable "pipeline_topic" {
  default = "ea-spin-topic"
}

variable "pipeline_gke_cluster" {
  default = "ea-cd-gke"
}

locals {
  bucket_name    = "pipeline-integration-${local.project_id}"
  pub_topic_name = "projects/${var.pipeline_project_id}/topics/${var.pipeline_topic}"
  gcr_sa_name    = "gcr-sa"
}

# Allow Pipeline Cloud Build service account to create workload and CRB in the app cluster
resource "google_project_iam_member" "pipeline-cloudbuild-access-to-gke" {
  role    = "roles/container.admin"
  project = "${local.project_id}"
  member  = "serviceAccount:${var.pipeline_project_number}@cloudbuild.gserviceaccount.com"
}

# Bucket to store application config files (deployment manifest, pipeline config files..etc)
resource "google_storage_bucket" "pipeline_bucket" {
  project       = "${local.project_id}"
  name          = "${local.bucket_name}"
  location      = "${var.region}"
  storage_class = "REGIONAL"
  force_destroy = "true"
}

# Create a service account  to access GCR of app project
resource "google_service_account" "gcr_sa" {
  project      = "${local.project_id}"
  account_id   = "${local.gcr_sa_name}"
  display_name = "${local.gcr_sa_name}"
}

# Create service account key
resource "google_service_account_key" "gcr_sa_key" {
  service_account_id = "${google_service_account.gcr_sa.name}"
}

# Project browser role is required to list images in the repository
# Refer https://github.com/spinnaker/spinnaker/issues/2407
resource "google_project_iam_member" "gcr_sa_browser" {
  role    = "roles/browser"
  project = "${local.project_id}"
  member  = "serviceAccount:${google_service_account.gcr_sa.email}"
}

# Grant GCR read permission for the service acccount
resource "google_storage_bucket_iam_member" "gcr_sa_read_access" {
  role   = "roles/storage.objectViewer"
  bucket = "asia.artifacts.${local.project_id}.appspot.com"
  member = "serviceAccount:${google_service_account.gcr_sa.email}"
}

# Grant GCS read permission for the service acccount
resource "google_storage_bucket_iam_member" "gcs_sa_read_access" {
  depends_on = [
    "google_storage_bucket.pipeline_bucket",
    "google_storage_bucket_iam_member.gcr_sa_read_access",
    "google_project_iam_member.gcr_sa_browser",
  ]

  role   = "roles/storage.objectViewer"
  bucket = "${google_storage_bucket.pipeline_bucket.name}"
  member = "serviceAccount:${google_service_account.gcr_sa.email}"
}

# Allow Pipeline Cloud Build service account to create notification on GCS bucket
resource "google_storage_bucket_iam_member" "pipeline-cloudbuild-gcs" {
  depends_on = [
    "google_storage_bucket_iam_member.gcs_sa_read_access",
  ]

  role   = "roles/storage.admin"
  bucket = "${google_storage_bucket.pipeline_bucket.name}"
  member = "serviceAccount:${var.pipeline_project_number}@cloudbuild.gserviceaccount.com"
}
