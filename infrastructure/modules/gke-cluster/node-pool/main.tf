# Create the Node Pool

resource "google_container_node_pool" "node_pool" {
  name = "${var.name}"
  cluster = "${var.cluster_name}"
  region = "${var.region}"
  project = "${var.project_id}"

  initial_node_count = "${var.initial_node_count}"

  autoscaling {
    min_node_count = "${var.min_node_count}"
    max_node_count = "${var.max_node_count}"
  }

  management {
    auto_repair = true
    auto_upgrade = true
  }


  node_config {
    preemptible = true
    image_type = "COS"
    machine_type = "${var.node_instance_type}"
    disk_size_gb = "${var.node_disk_size_gb}"

    service_account = "${var.service_account}"

    # Metadata concealment as per https://cloud.google.com/kubernetes-engine/docs/how-to/metadata-concealment
    # https://www.terraform.io/docs/providers/google/r/container_cluster.html#node_metadata
    workload_metadata_config {
      node_metadata = "SECURE"
    }

    # The list of instance tags applied to all nodes. Tags are used to identify valid sources or
    # targets for network firewalls.
    # tags = ["${var.cluster_name}-cluster", "${var.name}-node-pool"]

    # k8s labels that can be used for pod scheduling
    labels = "${var.labels}"
    # Minimal set of scopes as default; additional ones passed with var.oauth_scopes
    oauth_scopes = "${concat(list(
      "logging-write",
      "monitoring",
      "storage-ro",
    ), var.oauth_scopes)}"
  }
}
