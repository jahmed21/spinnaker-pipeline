#!/usr/bin/env bash

set -xeo pipefail

source /opt/halyard/additionalConfigMaps/common-functions.sh

# Enable debug for oauth2 and docker registry related code
kubectl exec $HALYARD_POD -- bash -c \
  "mkdir -p ~/.hal/default/profiles;cat ${ADDITIONAL_CONFIGMAP_DIR}/spinnaker-local.yml > ~/.hal/default/profiles/spinnaker-local.yml;"
