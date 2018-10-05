data "google_client_config" "current" {}

data "google_container_cluster" "gke_cluster" {
  project = "${local.project_id}"
  name    = "${module.app-gke.cluster_name}"
  region  = "${var.region}"
}

provider "kubernetes" {
  load_config_file       = "false"
  host                   = "https://${data.google_container_cluster.gke_cluster.endpoint}"
  cluster_ca_certificate = "${base64decode(data.google_container_cluster.gke_cluster.master_auth.0.cluster_ca_certificate)}"
  token                  = "${data.google_client_config.current.access_token}"
}

data "template_file" "docker-cfg" {
  template = <<JSON
{
  "auths": {
    "$${docker_server}": {
      "username": "_json_key",
      "password": $${password},
      "email": "$${email}",
      "auth": "$${auth}"
    }
  }
}
JSON

  vars {
    docker_server = "https://asia.gcr.io"
    email         = "${google_service_account.gcr_sa.email}"
    password      = "${jsonencode(replace(base64decode(google_service_account_key.gcr_sa_key.private_key), "\n", ""))}"
    auth          = "${base64encode("_json_key:${replace(base64decode(google_service_account_key.gcr_sa_key.private_key), "\n", "")}")}"
  }
}

resource "kubernetes_secret" "imagepullsecret" {
  metadata {
    name      = "gcr-image"
    namespace = "kube-system"

    annotations {
      "paas.ex.anz.com/repositories" = "app-service-12/sample-sb"
    }

    labels {
      "paas.ex.anz.com/cluster" = "${var.pipeline_gke_cluster}"
      "paas.ex.anz.com/project" = "${var.pipeline_project_id}"
    }
  }

  data {
    ".dockerconfigjson" = "${data.template_file.docker-cfg.rendered}"
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_secret" "project_imagepullsecret" {
  metadata {
    name      = "gcr-project"
    namespace = "kube-system"

    annotations {
      "paas.ex.anz.com/repositories" = "app-service-12"
    }

    labels {
      "paas.ex.anz.com/cluster" = "${var.pipeline_gke_cluster}"
      "paas.ex.anz.com/project" = "${var.pipeline_project_id}"
    }
  }

  data {
    ".dockerconfigjson" = "${data.template_file.docker-cfg.rendered}"
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_secret" "public_imagepullsecret" {
  metadata {
    name      = "gcr-public"
    namespace = "kube-system"

    labels {
      "paas.ex.anz.com/cluster" = "${var.pipeline_gke_cluster}"
      "paas.ex.anz.com/project" = "${var.pipeline_project_id}"
    }
  }

  data {
    ".dockerconfigjson" = "${data.template_file.docker-cfg.rendered}"
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_namespace" "staging" {
  "metadata" {
    name = "staging"
  }
}

resource "kubernetes_namespace" "testing" {
  "metadata" {
    name = "testing"
  }
}

resource "kubernetes_namespace" "production" {
  "metadata" {
    name = "production"
  }
}
