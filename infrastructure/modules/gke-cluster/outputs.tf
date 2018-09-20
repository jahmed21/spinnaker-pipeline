output "region" {
  value = "${google_container_cluster.cluster.region}"
}

output "project_id" {
  value = "${google_container_cluster.cluster.project}"
}

output "endpoint" {
  value = "${google_container_cluster.cluster.endpoint}"
}

output "cluster_name" {
  value = "${google_container_cluster.cluster.name}"
}

output "kubeconfig" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.cluster.name} --region ${google_container_cluster.cluster.region} --project ${google_container_cluster.cluster.project}"
}
