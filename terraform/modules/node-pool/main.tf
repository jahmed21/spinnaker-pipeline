resource "google_container_node_pool" "node_pool" {
  name       = "${var.name}"
  cluster    = "${var.cluster_name}"
  zone       = "${var.zone}"
  project    = "${var.project_id}"
  node_count = "${var.node_count}"

  management {
    auto_repair  = false
    auto_upgrade = false
  }

  node_config {
    image_type      = "COS"
    machine_type    = "${var.node_instance_type}"
    disk_size_gb    = "${var.node_disk_size_gb}"
    preemptible     = true
    service_account = "${var.service_account}"
    tags            = "${var.tags}"
    labels          = "${var.labels}"

    oauth_scopes = "${concat(list(
      "logging-write",
      "monitoring",
      "storage-ro",
      "cloud-platform",
      "https://www.googleapis.com/auth/source.read_write"
    ), var.oauth_scopes)}"
  }
}

output "id" {
  value = "${google_container_node_pool.node_pool.id}"
}
