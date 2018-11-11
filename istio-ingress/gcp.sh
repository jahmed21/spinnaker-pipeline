#!/bin/bash

set -xe

gsutil cp spinnaker-roer.nataram4.com/1_root/certs/ca.cert.pem gs://diwali-16838-halyard-config/ca-crt.pem
gsutil cp spinnaker-roer.nataram4.com/3_application/private/spinnaker-roer.nataram4.com.key.pem gs://diwali-16838-halyard-config/server-key.pem
gsutil cp spinnaker-roer.nataram4.com/3_application/certs/spinnaker-roer.nataram4.com.cert.pem gs://diwali-16838-halyard-config/server-crt.pem
