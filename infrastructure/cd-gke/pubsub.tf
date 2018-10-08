variable "app_project_number" {
  default = "391177193792"
}

locals {
  app_pubsub_serviceaccount = "service-${var.app_project_number}@gs-project-accounts.iam.gserviceaccount.com"
  spinnaker_pubsub_sa_name  = "spinnaker-pubsub"
  subscription_name         = "spin-pipeline"
}

# Create topic to receive application GCS notification
resource "google_pubsub_topic" "pubsub_topic" {
  name    = "ea-spin-topic"
  project = "${local.project_id}"
}

# Allow the application service account to publish to the topic created in this project
resource "google_pubsub_topic_iam_member" "publish_iam" {
  project = "${local.project_id}"
  member  = "serviceAccount:${local.app_pubsub_serviceaccount}"
  role    = "roles/pubsub.publisher"
  topic   = "${google_pubsub_topic.pubsub_topic.name}"
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

# Allow spinnaker service account to subscribe only to this subscription
resource "google_pubsub_subscription_iam_member" "spinnaker_pubsub_sa_role" {
  project      = "${local.project_id}"
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.spinnaker_pubsub_sa.email}"
  subscription = "${google_pubsub_subscription.spin_pipeline_subscription.name}"
}
