#!/usr/bin/env bash

set -eo pipefail

declare -A TO_BE_CONFIGURED_MAP

CONFIGMAP_STORAGE_NAME=app-kubeconfig-versions
SPINNAKER_NAMESPACE=spinnaker

# Create a temp directory for all files generated during this execution
#MYTMPDIR=$(mktemp -d /tmp/register-app-job.XXXX)
#trap "rm -vrf $MYTMPDIR" EXIT

#function tempFile() {
#  mktemp ${MYTMPDIR}/${1}.XXXXX
#}

function log() {
  >&2 echo
  >&2 echo "$(date): $@"
}

function getConfiguredVersion() {
  local secret=$1

  if ! kubectl -n $SPINNAKER_NAMESPACE get configmap $CONFIGMAP_STORAGE_NAME -o=jsonpath='{.metadata.name}' >/dev/null; then
    log "Creating configmap storage '$CONFIGMAP_STORAGE_NAME'"
    kubectl -n $SPINNAKER_NAMESPACE create configmap $CONFIGMAP_STORAGE_NAME >&2
  fi

  local version=$(kubectl -n $SPINNAKER_NAMESPACE get configmap $CONFIGMAP_STORAGE_NAME  -o yaml | yq r - "data.${secret}")

  if [[ -z "$version" || $version == null ]]; then
    log "'$secret' Not found in configmap, first time config?"
    version=0
  else
    log "Version from configmap: $version"
  fi

  echo $version
}

function getVersionFromSecret() {
  local secret=$1
  local version=$(kubectl -n $SPINNAKER_NAMESPACE get secret "$secret"  -o yaml | yq r - "metadata.resourceVersion" )

  if [[ -z "$version" ]]; then
    log "Error. Secret'$secret' not found"
    exit 1
  fi

  log "Version from secret: $version"
  echo $version
}

function compareVersion() {
  local secret=$1
  local configuredVersion=$(getConfiguredVersion $secret)
  local versionFromSecret=$(getVersionFromSecret $secret)

  if (( $versionFromSecret > $configuredVersion )); then
    log "Newer version of secret found. Current Version: $versionFromSecret, Previous Configured Version: $configuredVersion"
    TO_BE_CONFIGURED_MAP[$secret]=$versionFromSecret
  fi
}

function invokeHalScript() {

  local halyard_pods=$(kubectl -n $SPINNAKER_NAMESPACE get po \
            -l component=halyard,statefulset.kubernetes.io/pod-name \
            --field-selector status.phase=Running \
            -o jsonpath="{.items[*].metadata.name}")

  if [[ -z "$halyard_pods" ]]; then
    log "Error. Halyard not running"
    exit 1
  fi

  local first_halyard_pod=$(kubectl -n $SPINNAKER_NAMESPACE get po \
            -l component=halyard,statefulset.kubernetes.io/pod-name \
            --field-selector status.phase=Running \
            -o jsonpath="{.items[0].metadata.name}")

  log "Executing k8s-account-config.sh in [$first_halyard_pod]"
  log kubectl -n $SPINNAKER_NAMESPACE exec $first_halyard_pod -- bash /opt/halyard/additionalConfigMaps/k8s-account-config.sh  "${!TO_BE_CONFIGURED_MAP[@]}"
  kubectl -n $SPINNAKER_NAMESPACE exec $first_halyard_pod -- bash /opt/halyard/additionalConfigMaps/k8s-account-config.sh  "${!TO_BE_CONFIGURED_MAP[@]}"
}

function updateVersionInConfgMap() {
  local configMapYaml=$(kubectl -n $SPINNAKER_NAMESPACE get configmap $CONFIGMAP_STORAGE_NAME  -o yaml)

  log "ConfigMap content before [$configMapYaml]"

  for secret in "${!TO_BE_CONFIGURED_MAP[@]}"; do
    local newVersion="${TO_BE_CONFIGURED_MAP[$secret]}"
    log "Updating $secret version in configMap to $newVersion"
    configMapYaml=$(echo "$configMapYaml" | yq w - "data.${secret}" "\"${newVersion}\"")
  done

  log "ConfigMap content after [$configMapYaml]"

  echo "${configMapYaml}" | kubectl -n $SPINNAKER_NAMESPACE apply -f -
}

# Main logic starts here


if secretList=$(kubectl -n $SPINNAKER_NAMESPACE get secret --selector paas.ex.anz.com/type=kubeconfig -o=jsonpath='{.items[*].metadata.name}'); then
  for aSecret in $secretList; do
    log "Checking kubernetes account '$aSecret' for modification"
    compareVersion $aSecret
  done
fi

log "Number of secret to be configured is ${#TO_BE_CONFIGURED_MAP[@]}"

if (( ${#TO_BE_CONFIGURED_MAP[@]} == 0 )); then
  log "No processing required....."
  exit 0
fi

invokeHalScript

updateVersionInConfgMap
