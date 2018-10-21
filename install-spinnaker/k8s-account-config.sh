#!/usr/bin/env bash

# Invoked by register-app-job, to configure halyard with application's kubeconfig

set -eo pipefail

function configFile() {
  mkdir -p /home/spinnaker/.hal/app-config
  #mktemp /home/spinnaker/.hal/app-config/${1}.XXXXX
  echo /home/spinnaker/.hal/app-config/${1}
}

function log() {
  >&2 echo
  >&2 echo "$(date): $@"
}

function echoAndExec() {
  log "$@"
  eval "$@"
}

function getDataFromSecret() {
  local secretName=$1
  local key=$(echo "$2" | sed 's/\./\\./g')
  kubectl get secret $secretName -o=jsonpath="{.data.${key}}" | base64 --decode
}

function getLabelFromSecret() {
  local secretName=$1
  local key=$(echo "$2" | sed 's/\./\\./g')
  kubectl get secret $secretName -o=jsonpath="{.metadata.labels.${key}}"
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

function configureKubernetesAccount() {
  local configName=$1

  log "Getting details from secret $configName"

  local appProjectId=$(getLabelFromSecret $configName "paas.ex.anz.com/project")
  local appClusterName=$(getLabelFromSecret $configName "paas.ex.anz.com/cluster")
  local account_name="$(echo "${appProjectId}-${appClusterName}" | tr -s '[:punct:]' '-')"

  local kubeconfigFile=$(configFile ${appProjectId}-${appClusterName}.kubeconfig)
  getDataFromSecret $configName "kubeconfig" > $kubeconfigFile


  log "Creating kubernetes account '$account_name'"
  echoAndExec hal config provider kubernetes account \
            $(getCommandForAccount kubernetes "$account_name") \
            "$account_name" \
            --kubeconfig-file $kubeconfigFile \
            --omit-namespaces=kube-system,kube-public \
            --provider-version v2
}

for aSecret in "$@"; do
  configureKubernetesAccount $aSecret
done

# Apply  the config changes
hal config
hal deploy apply
