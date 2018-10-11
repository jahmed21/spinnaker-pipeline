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
_PUBSUB_SUBSCRIPTION_NAME="$(getAdditionalConfigValue $ADDITIONAL_CONFIGMAP_DIR pubsub-subscription-name)"
SPINNAKER_GCP_SA_KEY_JSON=${ADDITIONAL_SECRETS_DIR}/spinnaker-gcp-sa-access-key.json

# Configure pubsub account
ACCOUNT_NAME="pubsub"
COMMAND_MODE="add"

if $HAL_COMMAND config pubsub google subscription get $ACCOUNT_NAME 2>/dev/null; then
  COMMAND_MODE="edit"
fi

$HAL_COMMAND config pubsub google subscription $COMMAND_MODE $ACCOUNT_NAME \
        --subscription-name $_PUBSUB_SUBSCRIPTION_NAME \
        --json-path $SPINNAKER_GCP_SA_KEY_JSON \
        --project $_PROJECT_ID \
        --message-format "GCS"

$HAL_COMMAND config pubsub google enable

# Configure GCS Artifact account
ACCOUNT_NAME="gcs-artifact"
COMMAND_MODE="add"

if $HAL_COMMAND config artifact gcs account get $ACCOUNT_NAME 2>/dev/null; then
  COMMAND_MODE="edit"
fi
$HAL_COMMAND config artifact gcs account $COMMAND_MODE $ACCOUNT_NAME --json-path $SPINNAKER_GCP_SA_KEY_JSON

$HAL_COMMAND config artifact gcs enable
