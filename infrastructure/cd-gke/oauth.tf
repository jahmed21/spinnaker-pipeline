locals {
  google_oauth_client_secret_json = "spinnaker-oauth-client.json"
}

# Store service account key as bucket object
#resource "google_storage_bucket_object" "oauth-client-secret" {
#  name         = "${local.google_oauth_client_secret_json}"
#  content      = "${file(local.google_oauth_client_secret_json)}"
#  bucket       = "${google_storage_bucket.halyard_config.name}"
#  content_type = "application/json"
#}
