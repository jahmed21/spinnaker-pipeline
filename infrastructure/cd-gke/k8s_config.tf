data "google_client_config" "current" {}

data "google_container_cluster" "gke_cluster" {
  project = "${local.project_id}"
  name    = "${module.cd-gke.cluster_name}"
  region  = "${var.region}"
}

provider "kubernetes" {
  load_config_file       = "false"
  host                   = "https://${data.google_container_cluster.gke_cluster.endpoint}"
  cluster_ca_certificate = "${base64decode(data.google_container_cluster.gke_cluster.master_auth.0.cluster_ca_certificate)}"
  token                  = "${data.google_client_config.current.access_token}"
}

resource "kubernetes_namespace" "spinnaker_ns" {
  "metadata" {
    name = "spinnaker"
  }
}

resource "kubernetes_secret" "gcs_key" {
  metadata {
    name      = "spinnaker-gcs-key"
    namespace = "${kubernetes_namespace.spinnaker_ns.metadata.0.name}"

    labels {
      "paas.ex.anz.com/project" = "${local.project_id}"
    }
  }

  data {
    "key.json" = "${base64decode(google_service_account_key.spinnaker_gcs_key.private_key)}"
  }
}

resource "kubernetes_secret" "pubsub_key" {
  metadata {
    name      = "spinnaker-pubsub-key"
    namespace = "${kubernetes_namespace.spinnaker_ns.metadata.0.name}"

    labels {
      "paas.ex.anz.com/project" = "${local.project_id}"
    }
  }

  data {
    "key.json" = "${base64decode(google_service_account_key.spinnaker_pubsub_sa_key.private_key)}"
  }
}
