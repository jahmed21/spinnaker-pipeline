#!/usr/bin/env bash

set -xeo pipefail

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/hal.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function getDataFromSecret() {
  local secretName=$1
  local key=$2
  kubectl get secret $secretName -o=jsonpath="{.data.${key}}" | base64 --decode
}

function getCommandForAccount() {
  local accountType=$1
  local accountName=$2

  if hal config provider "$accountType" account get "$accountName" >/dev/null 2>&1; then
    echo "edit"
  else
    echo "add"
  fi
}

function configureDockerRegistry() {
  local configName=$1
  local server=$(getDataFromSecret $configName "server")
  local email=$(getDataFromSecret $configName "email")

  local repositories=$(getDataFromSecret $configName "repositories")
  local repo_param=""
  if [[ ! -z "$repositories" ]]; then
    repo_param="--repositories $repositories"
  fi

  local passwordFile=$(tempFile ${configName}.password)
  getDataFromSecret $configName "password" | tr -d '\n' > $passwordFile

  hal config provider docker-registry account \
        $(getCommandForAccount docker-registry "$configName") \
        "$configName" \
        --address "$server" \
        --username "_json_key" \
        --email "$email" \
        --password-file $passwordFile $repo_param
}

function scanForDockerRegistryConfiguration() {
  if local jsonConfigList=$(kubectl get secret -l type=dockerconfigjson -o=jsonpath='{.items[*].metadata.name}'); then
    for jsonConfig in $jsonConfigList; do
      echo "Processing dockerconfigjson '$jsonConfig'"
      configureDockerRegistry $jsonConfig
    done
  fi
}

scanForDockerRegistryConfiguration
