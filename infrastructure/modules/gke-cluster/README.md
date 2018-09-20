# Resource GKE Cluster

Module to create a private GKE cluster in a Shared VPC

## Usage

```
module "cluster" {
  source                  = "../../../modules/resource-gke-regional-cluster"
  region                  = "${var.region}"
  project_id              = "${data.google_project.service_project.project_id}"
  host_project_id         = "${var.host_project_id}"
  shared_vpc_name         = "${var.shared_vpc_name}"
  cluster_service_account = "limited-user@${data.google_project.service_project.project_id}.iam.gserviceaccount.com"

  master_authorized_cidr_blocks = [
    { cidr_block = "1.152.0.0/16" }
  ]
}
```
