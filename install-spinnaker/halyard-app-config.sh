#!/usr/bin/env bash

set -eo pipefail

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/hal.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function echoAndExec() {
  echo "$@"
  eval "$@"
}

function getDataFromSecret() {
  local secretName=$1
  local key=$2
  kubectl get secret $secretName -o=jsonpath="{.data.${key}}" | base64 --decode
}

function getLabelFromSecret() {
  local secretName=$1
  local key=$2
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

function configureDockerRegistryAccount() {
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

  echoAndExec hal config provider docker-registry account \
        $(getCommandForAccount docker-registry "$configName") \
        "$configName" \
        --address "$server" \
        --username "_json_key" \
        --email "$email" \
        --password-file $passwordFile $repo_param
}

function processDockerRegistryAccounts() {
  if local secretList=$(kubectl get secret -l type=dockerconfigjson -o=jsonpath='{.items[*].metadata.name}'); then
    for aSecret in $secretList; do
      echo "Processing docker-registry account '$aSecret'"
      configureDockerRegistryAccount $aSecret
    done
  fi
}

function configureKubernetesAccount() {
  local configName=$1

  local appClusterName=$(getLabelFromSecret $configName "app-cluster")
  local registries=$(kubectl get secret -l type=dockerconfigjson,app-cluster=$appClusterName -o=jsonpath='{.items[*].metadata.name}' | tr -s '[:blank:][:space:]' ',,')
  local reg_param=""
  if [[ ! -z "$registries" ]]; then
    reg_param="--docker-registries $registries"
  fi

  local kubeconfigFile=$(tempFile ${configName}.kubeconfig)
  getDataFromSecret $configName "kubeconfig" > $kubeconfigFile
  local context="$(kubectl --kubeconfig $kubeconfigFile config current-context)"
  local account_name="$(echo "$context" | tr -s '[:punct:]' '-')"

  echoAndExec hal config provider kubernetes account \
            $(getCommandForAccount kubernetes "$account_name") \
            "$account_name" \
            --context "$context" \
            --kubeconfig-file $kubeconfigFile \
            --omit-namespaces=kube-system,kube-public \
            --provider-version v2 $reg_param
}

function processKubernetesAccounts() {
  if local secretList=$(kubectl get secret -l type=kubeconfig -o=jsonpath='{.items[*].metadata.name}'); then
    for aSecret in $secretList; do
      echo "Processing kubernetes account '$aSecret'"
      configureKubernetesAccount $aSecret
    done
  fi
}

processDockerRegistryAccounts
processKubernetesAccounts

# Apply  the config changes
hal deploy apply
