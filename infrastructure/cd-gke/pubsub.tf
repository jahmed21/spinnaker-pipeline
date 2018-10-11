locals {
  subscription_name = "spin-pipeline-trigger"
  topic_name        = "spin-pipeline"
  ci_project_number = "924344399848"
}

# Create topic to receive application GCS notification
resource "google_pubsub_topic" "pubsub-topic" {
  name    = "${local.topic_name}"
  project = "${local.project_id}"
}

# Create a subscription for spinnaker
resource "google_pubsub_subscription" "pipeline-subscription" {
  project = "${local.project_id}"
  name    = "${local.subscription_name}"
  topic   = "${google_pubsub_topic.pubsub-topic.name}"
}

# Allow spinnaker service account to subscribe only to this subscription
resource "google_pubsub_subscription_iam_member" "pipeline-subscription-iam" {
  project      = "${local.project_id}"
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.spinnaker_gcs.email}"
  subscription = "${google_pubsub_subscription.pipeline-subscription.name}"
}

# Allow Cloud Build service account to attach publisher (Application GCS bucket notification) to topic
resource "google_project_iam_member" "cloudbuild-access-to-pubsub" {
  project = "${local.project_id}"
  role    = "roles/pubsub.admin"
  member  = "serviceAccount:${local.ci_project_number}@cloudbuild.gserviceaccount.com"
}
