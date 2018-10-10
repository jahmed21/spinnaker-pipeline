#!/usr/bin/env bash

set -xeo pipefail

ADDITIONAL_CONFIGMAP_DIR="/opt/halyard/additionalConfigMaps"

# Below codes are executed  inside halyard pod
HALYARD_POD=$(kubectl get po \
            -l component=halyard,statefulset.kubernetes.io/pod-name \
            --field-selector status.phase=Running \
            -o jsonpath="{.items[0].metadata.name}")

# Enable debug for oauth2 and docker registry related code
kubectl exec $HALYARD_POD -- bash -c \
  "mkdir -p ~/.hal/default/profiles;cat ${ADDITIONAL_CONFIGMAP_DIR}/spinnaker-local.yml > ~/.hal/default/profiles/spinnaker-local.yml;"
