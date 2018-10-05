variable "pipeline_project_id" {
  default = "cd-pipeline-1"
}

variable "pipeline_project_number" {
  default = "693677694217"
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

# Bucket to store application config files (deployment manifest, pipeline config files..etc)
resource "google_storage_bucket" "pipeline_bucket" {
  project       = "${local.project_id}"
  name          = "${local.bucket_name}"
  location      = "${var.region}"
  storage_class = "REGIONAL"
  force_destroy = "true"
}

# Send notification to pipeline topic (created under spinnaker project) whenever there are changes in this bucket
resource "google_storage_notification" "pipeline_bucket_notification" {
  bucket         = "${google_storage_bucket.pipeline_bucket.name}"
  payload_format = "JSON_API_V1"
  topic          = "${local.pub_topic_name}"
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

# Grant read permission for the service acccount
resource "google_storage_bucket_iam_member" "gcr_sa_read_access" {
  bucket = "asia.artifacts.${local.project_id}.appspot.com"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.gcr_sa.email}"
}

# Allow Pipeline Cloud Build service account create workload in the cluster and create ClusterRoleBinding
resource "google_project_iam_member" "pipeline-cloudbuild-access-to-gke" {
  project = "${local.project_id}"
  role    = "roles/container.admin"
  member  = "serviceAccount:${var.pipeline_project_number}@cloudbuild.gserviceaccount.com"
}