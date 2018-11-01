locals {
  cd_project_id = "istio-spin-21468"
}

# Give permission to spinnaker service account created in services to check images from launchpad docker registries
resource "google_storage_bucket_iam_member" "spinnaker-check-images-asia" {
  bucket = "asia.artifacts.${local.project_id}.appspot.com"
  role        = "roles/storage.objectViewer"
  member      = "serviceAccount:spinnaker-gcs-sa@${local.cd_project_id}.iam.gserviceaccount.com"
}

# Allow spinnaker SA to have browser role on LaunchPad project (where images are stored)
# Project browser role is required to list images in the repository
# Refer https://github.com/spinnaker/spinnaker/issues/2407
resource "google_project_iam_member" "spinnaker-browse-artifacts" {
  role    = "roles/browser"
  project = "${local.project_id}"
  member = "serviceAccount:spinnaker-gcs-sa@${local.cd_project_id}.iam.gserviceaccount.com"
}
