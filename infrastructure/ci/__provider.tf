provider "google" {
  region  = "${local.region}"
  version = "~> 1.16"
}

terraform {
  required_version = "> 0.11.8"
}
