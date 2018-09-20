#######################################
# GKE Cluster
#######################################

# Additional stuff we could do from google feedback:
# - Check drift - eg for all namespaces are the network policies there, is the pod security policy there? -> check kubecfg, could be useful but can be very complicated.
# - enforce resource requests - pod security policies or limit ranges -> Does defaults. - https://kubernetes.io/docs/concepts/policy/resource-quotas/
# - limit pod autoscaler upper range?  - https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/
# - vertical application scaler - coming later
# - network limits - need istio to do rate limiting
# - always pull images admission controller
# Recommended: https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#is-there-a-recommended-set-of-admission-controllers-to-use

# Create GKE Private Cluster
resource "google_container_cluster" "cluster" {
  name    = "${var.name}"
  region  = "${var.region}"
  project = "${data.google_project.service_project.project_id}"

  # Private GKE
  #private_cluster        = true
  #master_ipv4_cidr_block = "${var.master_ipv4_cidr_block}"

  # Optional binary authorization
  enable_binary_authorization = "${var.enable_binary_authorization}"

  min_master_version = "${var.kubernetes_version}"
  node_version       = "${var.kubernetes_version}"

  # Set a maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "${var.maintenance_window_start_time}"
    }
  }

  # https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#disable_abac
  enable_legacy_abac = false

  addons_config {
    # https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#disable_kubernetes_dashboard
    kubernetes_dashboard {
      # Disable dashboard
      disabled = true
    }

    # TODO Tune this
    # https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#restrict_with_network_policy
    network_policy_config {
      # enable network policy
      disabled = false
    }

    http_load_balancing {
      # enable http load balancing
      disabled = false
    }

    horizontal_pod_autoscaling {
      # enable horizontal pod autoscaler
      disabled = false
    }
  }

  # Declare node pools independently of clusters
  remove_default_node_pool = true

  node_pool = {
    name = "default-pool"
  }

  # Ensure cluster is not recreated when pool configuration changes
  lifecycle = {
    ignore_changes = [
      "node_pool",
    ]
  }
}

module "default_node_pool" {
  source = "node-pool"

  project_id         = "${data.google_project.service_project.project_id}"
  name               = "default-pool"
  cluster_name       = "${google_container_cluster.cluster.name}"
  region             = "${var.region}"
  initial_node_count = "${var.initial_node_count}"
  min_node_count     = "${var.min_node_count}"
  max_node_count     = "${var.max_node_count}"
  node_instance_type = "${var.node_instance_type}"
  node_disk_size_gb  = "${var.node_disk_size_gb}"
  service_account    = "${var.cluster_service_account}"
  oauth_scopes       = "${var.oauth_scopes}"
}
