locals {
  project_id = "ci-project-002"
  region     = "asia-southeast1"
}

data "google_project" "this_projecct" {
  project_id = "${local.project_id}"
}
