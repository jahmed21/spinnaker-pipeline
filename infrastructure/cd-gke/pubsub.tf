locals {
  spinnaker_pubsub_sa_name     = "spinnaker-pubsub-sa"
  spinnaker_pubsub_sa_key_name = "spinnaker-pubsub-sa-key.json"
  subscription_name            = "spin-pipeline-trigger"
  topic_name                   = "spin-pipeline"
}

# Create topic to receive application GCS notification
resource "google_pubsub_topic" "pubsub_topic" {
  name    = "${local.topic_name}"
  project = "${local.project_id}"
}

# Create a subscription for spinnaker
resource "google_pubsub_subscription" "spin_pipeline_subscription" {
  project = "${local.project_id}"
  name    = "${local.subscription_name}"
  topic   = "${google_pubsub_topic.pubsub_topic.name}"
}

# Create service account for spinnaker to receive pubsub notifications
resource "google_service_account" "spinnaker_pubsub_sa" {
  project      = "${local.project_id}"
  account_id   = "${local.spinnaker_pubsub_sa_name}"
  display_name = "${local.spinnaker_pubsub_sa_name}"
}

# Create service account key for spinnaker pubsub
resource "google_service_account_key" "spinnaker_pubsub_sa_key" {
  service_account_id = "${google_service_account.spinnaker_pubsub_sa.name}"
}

# Store service account key as bucket object
resource "google_storage_bucket_object" "spinnaker_pubsub_sa_key" {
  name         = "${local.spinnaker_pubsub_sa_key_name}"
  content      = "${base64decode(google_service_account_key.spinnaker_pubsub_sa_key.private_key)}"
  bucket       = "${google_storage_bucket.halyard_config.name}"
  content_type = "application/json"
}

# Allow spinnaker service account to subscribe only to this subscription
resource "google_pubsub_subscription_iam_member" "spinnaker_pubsub_sa_role" {
  project      = "${local.project_id}"
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.spinnaker_pubsub_sa.email}"
  subscription = "${google_pubsub_subscription.spin_pipeline_subscription.name}"
}

# Allow Cloud Build service account to attach publisher to topic
resource "google_project_iam_member" "cloudbuild-access-to-pubsub" {
  project = "${local.project_id}"
  role    = "roles/pubsub.admin"
  member  = "serviceAccount:${data.google_project.this_projecct.number}@cloudbuild.gserviceaccount.com"
}
