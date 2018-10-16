#!/usr/bin/env bash

ADDITIONAL_CONFIGMAP_DIR="/opt/halyard/additionalConfigMaps"
ADDITIONAL_SECRETS_DIR="/opt/halyard/additionalSecrets"
HALYARD_POD=$(kubectl get po \
            -l component=halyard,statefulset.kubernetes.io/pod-name \
            --field-selector status.phase=Running \
            -o jsonpath="{.items[0].metadata.name}")

function _getValue() {
  local dir=$1
  local fileName=$2
  local filePath="${dir}/${fileName}"
  if [[ -f "$filePath" && -r "$filePath" ]]; then
    cat "$filePath"
  fi
}

function _getFilePath() {
  local dir=$1
  local fileName=$2
  local filePath="${dir}/${fileName}"
  if [[ -f "$filePath" && -r "$filePath" ]]; then
    echo "$filePath"
  fi
}

function getConfigValue() {
  local config_name=$1
  _getValue $ADDITIONAL_CONFIGMAP_DIR  $config_name
}

function getSecretValue() {
  local config_name=$1
  _getValue $ADDITIONAL_SECRETS_DIR  $config_name
}

function getConfigFilePath() {
  local config_name=$1
  _getFilePath $ADDITIONAL_CONFIGMAP_DIR  $config_name
}

function getSecretFilePath() {
  local config_name=$1
  _getFilePath $ADDITIONAL_SECRETS_DIR  $config_name
}

function getCommandMode() {
  local config_name=$1
  shift
  local config_type="$@"

  local command_mode="add"
  if $HAL_COMMAND config $config_type get $config_name >/dev/null 2>/dev/null; then
    command_mode="edit"
  fi

  echo "$command_mode"
}