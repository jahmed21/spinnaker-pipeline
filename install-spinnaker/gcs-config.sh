#!/usr/bin/env bash

set -xeo pipefail

ADDITIONAL_CONFIGMAP_DIR="/opt/halyard/additionalConfigMaps"
ADDITIONAL_SECRETS_DIR="/opt/halyard/additionalSecrets"

getAdditionalConfigValue() {
  local dir=$1
  local fileName=$2
  local filePath="${dir}/${fileName}"
  if [[ -f "$filePath" && -r "$filePath" ]]; then
    cat "$filePath"
  fi
}

_PROJECT_ID="$(getAdditionalConfigValue $ADDITIONAL_CONFIGMAP_DIR project-id)"

# Configure GCS storage for spinnaker
GCS_JSON_KEY_PATH=${ADDITIONAL_SECRETS_DIR}/gcs.json

$HAL_COMMAND config storage gcs edit \
                  --project "${_PROJECT_ID}" \
                  --json-path $GCS_JSON_KEY_PATH \
                  --bucket "${_PROJECT_ID}-spinnaker-config" \
                  --no-validate

$HAL_COMMAND config storage edit --type gcs
