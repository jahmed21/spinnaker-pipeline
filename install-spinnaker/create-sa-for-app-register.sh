#!/usr/bin/env bash

set -eo pipefail
set +x

CD_PROJECT_ID=$1
CLOUDBUILD_SERVICE_ACCOUNT=$2
K8S_SA_NAME="app-register-sa"
K8S_SA_NAMESPACE="default"

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/register-app.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function log() {
  >&2 echo 
  >&2 echo "$(date): $@"
}

# Create service account for spinnaker to connect and deploy in the target application cluster
function createAppServiceAccount() {
  log  "Creating service-account $K8S_SA_NAME "

  local file=$(tempFile app-sa)
  cat <<EOF_KUBECTL > $file
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${K8S_SA_NAME}
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: secret-writer
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${K8S_SA_NAME}-rb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: secret-writer
subjects:
- kind: ServiceAccount
  name: ${K8S_SA_NAME}
EOF_KUBECTL


  # validate the config file
  kubeval $file

  cat $file

  kubectl -n $K8S_SA_NAMESPACE apply -f $file
}

# Create kubeconfig for spinnaker to connect to target app
function createKubeconfigForSA() {
  local kubeconfig_file=$1
  local secret=""

  if ! secret="$(kubectl -n $K8S_SA_NAMESPACE get serviceaccount $K8S_SA_NAME -o 'jsonpath={.secrets[0].name}' 2>/dev/null)"; then
    echo "Secret for serviceaccounts \"$K8S_SA_NAME\" not found." >&2
    exit 2
  fi

  if [[ -z "$secret" ]]; then
    echo "Secret for serviceaccounts \"$K8S_SA_NAME\" not found." >&2
    exit 2
  fi

  log "Creating kubeconfig file with token"

  # context
  local context="$(kubectl config current-context)"

  # cluster
  local cluster="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"$context\")].context.cluster}")"
  local server="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"$cluster\")].cluster.server}")"
  local ca_crt="$(tempFile ca_crt)"
  kubectl -n $K8S_SA_NAMESPACE get secret "$secret" -o "jsonpath={.data.ca\.crt}" | base64 -d > $ca_crt

  # token
  local token="$(kubectl -n $K8S_SA_NAMESPACE get secret "$secret" -o "jsonpath={.data.token}" | base64 -d)"
  local namespace="$K8S_SA_NAMESPACE"

  kubectl --kubeconfig $kubeconfig_file config set-credentials "$K8S_SA_NAME" --token="$token"
  kubectl --kubeconfig $kubeconfig_file config set-cluster "$cluster" --server="$server" --certificate-authority="$ca_crt" --embed-certs
  kubectl --kubeconfig $kubeconfig_file config set-context "$namespace" --cluster="$cluster" --namespace="$namespace" --user="${K8S_SA_NAME}"
  kubectl --kubeconfig $kubeconfig_file config use-context "$namespace"

  log "Test create"
  kubectl --kubeconfig $kubeconfig_file create secret generic test

  log "Test delete"
  kubectl --kubeconfig $kubeconfig_file delete secret test
}

function publishKubeconfigFile() {
  local kubeconfig_file=$1
  log "Storing kubeconfig at  gs://${CD_PROJECT_ID}-app-config/app-register.kubeconfig"
  gsutil cp $kubeconfig_file  gs://${CD_PROJECT_ID}-app-config/app-register.kubeconfig
}

# https://github.com/coreos/prometheus-operator/issues/357
# https://cloud.google.com/kubernetes-engine/docs/how-to/role-based-access-control#defining_permissions_in_a_role
function grantMeToCreateGKERole() {
  log "Allowing myself to create Role in GKE !!!!"
  kubectl create clusterrolebinding cloudbuild-cluster-admin-binding  \
              --dry-run \
              --clusterrole cluster-admin \
              --output yaml \
              --user=${CLOUDBUILD_SERVICE_ACCOUNT} | kubectl apply -f -
}

set +x
grantMeToCreateGKERole
createAppServiceAccount
KUBECONFIG_FILE="$(tempFile kubeconfig)"
createKubeconfigForSA $KUBECONFIG_FILE
publishKubeconfigFile $KUBECONFIG_FILE
