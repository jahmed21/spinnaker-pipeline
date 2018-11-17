variable "nat_gw_name" {}
variable "vpc_network_name" {}
variable "region" {}

data "template_file" "create_nat_gw_gcloud_cmds" {
  count = "${var.nat_gw_name == "" ? 0 : 1}"

  template = <<EOF
set -ex \
&& gcloud beta compute routers create $${router_name} \
            --network=$${network_name} \
            --region=$${region} \
&& gcloud beta compute routers nats create $${nat_gw_name} \
            --router=$${router_name} \
            --region=$${region} \
            --auto-allocate-nat-external-ips \
            --nat-primary-subnet-ip-ranges
EOF

  vars {
    router_name  = "${var.nat_gw_name}-router"
    nat_gw_name  = "${var.nat_gw_name}"
    network_name = "${var.vpc_network_name}"
    region       = "${var.region}"
  }
}

data "template_file" "destroy_nat_gw_gcloud_cmds" {
  count = "${var.nat_gw_name == "" ? 0 : 1}"

  template = <<EOF
set -ex \
&& gcloud beta compute routers nats delete $${nat_gw_name} --region=$${region} --router=$${router_name} \
&& gcloud beta compute routers delete $${router_name} --region=$${region}
EOF

  vars {
    router_name = "${var.nat_gw_name}-router"
    nat_gw_name = "${var.nat_gw_name}"
    region      = "${var.region}"
  }
}

resource "null_resource" "nat_gw" {
  count = "${var.nat_gw_name == "" ? 0 : 1}"

  triggers {
    sha256 = "${base64sha256(data.template_file.create_nat_gw_gcloud_cmds.rendered)}"
  }

  provisioner "local-exec" {
    command = "${data.template_file.create_nat_gw_gcloud_cmds.rendered}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "${data.template_file.destroy_nat_gw_gcloud_cmds.rendered}"
  }
}
