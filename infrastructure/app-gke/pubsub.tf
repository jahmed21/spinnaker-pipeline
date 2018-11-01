locals {
  bucket_name        = "${local.project_id}-spinnaker-artifacts"
  ci_project_number  = "924344399848"
  spinnaker_sa_email = "spinnaker-gcs-sa@istio-spin-21468.iam.gserviceaccount.com"
}

# Allow EX Cloud Build service account to create workload and CRB in the app cluster
resource "google_project_iam_member" "pipeline-cloudbuild-access-to-gke" {
  role    = "roles/container.admin"
  project = "${local.project_id}"
  member  = "serviceAccount:${local.ci_project_number}@cloudbuild.gserviceaccount.com"
}

# Bucket to store application config files (deployment manifest, pipeline config files..etc)
resource "google_storage_bucket" "services_bucket" {
  project       = "${local.project_id}"
  name          = "${local.bucket_name}"
  location      = "${local.region}"
  storage_class = "REGIONAL"
  force_destroy = "true"
}

# Grant GCS read permission for the service acccount
resource "google_storage_bucket_iam_member" "spinnaker-bucket-read-access" {
  role   = "roles/storage.objectViewer"
  bucket = "${google_storage_bucket.services_bucket.name}"
  member = "serviceAccount:${local.spinnaker_sa_email}"
}

# Allow EX Cloud Build service account to create notification on GCS bucket
resource "google_storage_bucket_iam_member" "ex-cloudbuild-gcs" {
  role   = "roles/storage.admin"
  bucket = "${google_storage_bucket.services_bucket.name}"
  member = "serviceAccount:${local.ci_project_number}@cloudbuild.gserviceaccount.com"
}
