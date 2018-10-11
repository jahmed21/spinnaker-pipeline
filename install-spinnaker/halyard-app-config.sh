#!/usr/bin/env bash

# Invoked by register-app cloudbuild (register-app.sh), to configure halyard with application's kubeconfig

set -eo pipefail

function configFile() {
  mkdir -p /home/spinnaker/.hal/app-config
  #mktemp /home/spinnaker/.hal/app-config/${1}.XXXXX
  echo /home/spinnaker/.hal/app-config/${1}
}

function echoAndExec() {
  echo "$@"
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

  local appClusterName=$(getLabelFromSecret $configName "paas.ex.anz.com/cluster")
  local appProjectId=$(getLabelFromSecret $configName "paas.ex.anz.com/project")

  local kubeconfigFile=$(configFile ${appProjectId}-${appClusterName}.kubeconfig)
  getDataFromSecret $configName "kubeconfig" > $kubeconfigFile

  local account_name="$(echo "${appProjectId}-${appClusterName}" | tr -s '[:punct:]' '-')"
  echo "Creating kubernetes account '$account_name'"
  echoAndExec hal config provider kubernetes account \
            $(getCommandForAccount kubernetes "$account_name") \
            "$account_name" \
            --kubeconfig-file $kubeconfigFile \
            --omit-namespaces=kube-system,kube-public \
            --provider-version v2
}

function processKubernetesAccounts() {
  if local secretList=$(kubectl get secret --selector paas.ex.anz.com/type=kubeconfig -o=jsonpath='{.items[*].metadata.name}'); then
    for aSecret in $secretList; do
      echo "Processing kubernetes account '$aSecret'"
      configureKubernetesAccount $aSecret
    done
  fi
}

echo

processKubernetesAccounts

# Apply  the config changes
hal config
hal deploy apply
