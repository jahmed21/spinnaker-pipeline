# Find Project (Service).
data "google_project" "service_project" {
  project_id = "${var.project_id}"
}
