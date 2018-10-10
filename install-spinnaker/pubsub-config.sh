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

# Configure pubsub
PUBSUB_JSON_KEY_PATH=${ADDITIONAL_SECRETS_DIR}/pubsub.json

PUBSUB_NAME="spin-pipeline"
COMMAND_MODE="add"

if $HAL_COMMAND config pubsub google subscription get $PUBSUB_NAME 2>/dev/null; then
  COMMAND_MODE="edit"
fi

$HAL_COMMAND config pubsub google subscription $COMMAND_MODE $PUBSUB_NAME \
        --subscription-name $_PUBSUB_SUBSCRIPTION_NAME \
        --json-path $PUBSUB_JSON_KEY_PATH \
        --project $_PROJECT_ID \
        --message-format "GCS"

$HAL_COMMAND config pubsub google enable
