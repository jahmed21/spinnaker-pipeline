#!/usr/bin/env bash

set -xeo pipefail

source /opt/halyard/additionalConfigMaps/common-functions.sh

_PROJECT_ID="$(getConfigValue project-id)"
_PUBSUB_SUBSCRIPTION_NAME="$(getConfigValue pubsub-subscription-name)"
SPINNAKER_GCP_SA_KEY_JSON=$(getSecretFilePath spinnaker-gcp-sa-access-key.json)

# Configure pubsub account
ACCOUNT_NAME="spin-gcs-subscriper"
COMMAND_MODE=$(getCommandMode $ACCOUNT_NAME "pubsub google subscription") 

$HAL_COMMAND config pubsub google subscription $COMMAND_MODE $ACCOUNT_NAME \
        --subscription-name $_PUBSUB_SUBSCRIPTION_NAME \
        --json-path $SPINNAKER_GCP_SA_KEY_JSON \
        --project $_PROJECT_ID \
        --message-format "GCS"

$HAL_COMMAND config pubsub google enable

# Configure GCS Artifact account
ACCOUNT_NAME="spin-gcs-artifact-reader"
COMMAND_MODE=$(getCommandMode $ACCOUNT_NAME "artifact gcs account") 

$HAL_COMMAND config artifact gcs account $COMMAND_MODE $ACCOUNT_NAME \
          --json-path $SPINNAKER_GCP_SA_KEY_JSON

$HAL_COMMAND config artifact gcs enable