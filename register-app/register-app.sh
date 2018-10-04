#!/usr/bin/env bash

set -eo pipefail

# Process command line arguments
function usage() {
echo
cat <<EOF
usage $(basename $0)
  --ex-project    Project Id of the Spinnaker deployment project
  --ex-cluster    Spinnaker GKE Cluster name
  --ex-namespace  k8s namespace where spinnaker is deployed (default to 'spinnaker')
  --app-project   Project Id of the Application to be integrated with Spinnaker
  --app-cluster   Application GKE Cluster name
  --sa-name       Name of the service account to be created in Application GKE for spinnaker to connect and deploy (default to 'ex-spinnaker')
  --region        GCP Region (default to 'australia-southeast1')
  --clean         Uninstall previous helm installation first
EOF
exit 1
}

TEMP=$(getopt -o h --long ex-cluster:,ex-project-id:,ex-namespace:,app-cluster:,app-project-id:,region:,sa-name: -n 'register-app.sh' -- "$@")
if [ $? != 0 ] ; then 
   echo "Terminating..." >&2 
   exit 2
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

_REGION="australia-southeast1"
_EX_CLUSTER=""
_EX_PROJECT_ID=""
_EX_NAMESPACE="spinnaker"
_APP_CLUSTER=""
_APP_PROJECT_ID=""
_APP_NAMESPACE="kube-system"
_APP_CLUSTER_SA_NAME="ex-spinnaker"

_APP_CLUSTER_KUBECONTEXT=""
_EX_CLUSTER_KUBECONTEXT=""

while true ; do
	case "$1" in
    --ex-cluster) _EX_CLUSTER=$2; shift 2;;
    --ex-project-id) _EX_PROJECT_ID=$2; shift 2;;
    --app-cluster) _APP_CLUSTER=$2; shift 2;;
    --app-project-id) _APP_PROJECT_ID=$2; shift 2;;
    --region) _REGION=$2; shift 2;;
	  --) shift ; break ;;
	  *) echo "Internal error!" ; usage ;;
	esac
done

if [[ ! -z "$*" \
      || -z "${_EX_CLUSTER}" \
      || -z "${_EX_PROJECT_ID}" \
      || -z "${_APP_CLUSTER}" \
      || -z "${_APP_PROJECT_ID}" \
      ]]; then
  usage
fi

# Done processing command line arguments

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/register-app.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function getKubeContext() {
    echo
    echo "Getting kubeconfig for $_APP_CLUSTER cluster"
    gcloud container clusters get-credentials ${_APP_CLUSTER} --region ${_REGION} --project ${_APP_PROJECT_ID}
    _APP_CLUSTER_KUBECONTEXT=$(kubectl config current-context)
    echo "Context: $_APP_CLUSTER_KUBECONTEXT"

    echo
    echo "Getting kubeconfig for $_EX_CLUSTER cluster"
    gcloud container clusters get-credentials ${_EX_CLUSTER} --region ${_REGION} --project ${_EX_PROJECT_ID}
    _EX_CLUSTER_KUBECONTEXT=$(kubectl config current-context)
    echo "Context: $_EX_CLUSTER_KUBECONTEXT"
}

function appClusterKubectl() {
  kubectl --context "$_APP_CLUSTER_KUBECONTEXT" --namespace "$_APP_NAMESPACE" $@
}

function exClusterKubectl() {
  kubectl --context "$_EX_CLUSTER_KUBECONTEXT" --namespace "$_EX_NAMESPACE" $@
}

# Create service account for spinnaker to connect and deploy in the target application cluster
function createAppServiceAccount() {
  echo
  echo  "Creating service-account $_APP_CLUSTER_SA_NAME in $_APP_CLUSTER cluster"

  local file=$(tempFile app-sa)
  cat <<EOF_KUBECTL > $file
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    paas.ex.anz.com/cluster: ${_EX_CLUSTER}
  name: ${_APP_CLUSTER_SA_NAME}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    paas.ex.anz.com/cluster: ${_EX_CLUSTER}
  name: ${_APP_CLUSTER_SA_NAME}-crb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: ${_APP_CLUSTER_SA_NAME}
  namespace: ${_APP_NAMESPACE}
EOF_KUBECTL


  # validate the config file
  kubeval $file

  appClusterKubectl apply -f $file
}

# Create kubeconfig for spinnaker to connect to target app
function createAppKubeConfigInExCluster() {
  local secret=""

  if ! secret="$(appClusterKubectl get serviceaccount $_APP_CLUSTER_SA_NAME -o 'jsonpath={.secrets[0].name}' 2>/dev/null)"; then
    echo "Secret for serviceaccounts \"$_APP_CLUSTER_SA_NAME\" not found." >&2
    exit 2
  fi

  if [[ -z "$secret" ]]; then
    echo "Secret for serviceaccounts \"$_APP_CLUSTER_SA_NAME\" not found." >&2
    exit 2
  fi

  # context
  local context="$_APP_CLUSTER_KUBECONTEXT"

  # cluster
  local cluster="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"$context\")].context.cluster}")"
  local server="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"$cluster\")].cluster.server}")"

  # token
  local ca_crt="$(tempFile ca_crt)"
  appClusterKubectl get secret "$secret" -o "jsonpath={.data.ca\.crt}" | openssl enc -d -base64 -A > $ca_crt
  local token="$(appClusterKubectl get secret "$secret" -o "jsonpath={.data.token}" | openssl enc -d -base64 -A)"

  local kubeconfig_file="$(tempFile kubeconfig)"
  kubectl --kubeconfig $kubeconfig_file config set-credentials "$_APP_CLUSTER_SA_NAME" --token="$token"
  kubectl --kubeconfig $kubeconfig_file config set-cluster "$cluster" --server="$server" --certificate-authority="$ca_crt" --embed-certs

  # Register all namespaces as context in spinnaker

  if local namespace_list=$(appClusterKubectl get namespace -o=jsonpath='{.items[*].metadata.name}'); then
    for namespace in $namespace_list; do
      if [[ $namespace =~ kube ]]; then
        echo "Skipping namespace '$namespace'"
        continue
      fi
      kubectl --kubeconfig $kubeconfig_file config set-context "$namespace" --cluster="$cluster" --namespace="$namespace" --user="${_APP_CLUSTER_SA_NAME}"
    done
  fi
  kubectl --kubeconfig $kubeconfig_file config use-context "default"

  kubectl --kubeconfig $kubeconfig_file cluster-info > /dev/null

  local sec_name=$(echo "${_APP_CLUSTER}-kubeconfig" | tr -s '[:punct:]' '-')
  local ex_secret_file=$(tempFile ex-kubeconfig)

  echo
  echo "About to create kubeconfig secret '$sec_name' in $_EX_CLUSTER cluster"
  exClusterKubectl create secret generic "$sec_name" \
    --from-file=kubeconfig="$kubeconfig_file" \
    --dry-run -o yaml \
    | yq w - 'metadata.labels.app-cluster' "$_APP_CLUSTER" \
    | yq w - 'metadata.labels.type' "kubeconfig" \
    | yq w - 'metadata.labels.[paas.ex.anz.com/app-cluster]' "$_APP_CLUSTER" \
    | yq w - 'metadata.labels.[paas.ex.anz.com/type]' "kubeconfig" \
    > $ex_secret_file

  # validate the config file
  kubeval $ex_secret_file

  exClusterKubectl apply -f $ex_secret_file
}

function getDockerConfigSecretNameFromAppCluster() {
  appClusterKubectl get secret \
      --field-selector type=kubernetes.io/dockerconfigjson \
      --selector paas.ex.anz.com/cluster=$_EX_CLUSTER \
      -o=jsonpath='{.items[*].metadata.name}'
}

function createDockerConfigSecretInExCluster() {
  local hcScript=$(tempFile  halyard-config)

  if local secretList="$(getDockerConfigSecretNameFromAppCluster)"; then
    for dcSecret in $secretList
    do
      local docker_server=$(appClusterKubectl get secret $dcSecret --output='jsonpath={.data.\.dockerconfigjson}' | base64 --decode | jq -Mr '.auths | to_entries[] | .key')
      local email=$(appClusterKubectl get secret $dcSecret --output='jsonpath={.data.\.dockerconfigjson}' | base64 --decode | jq -Mr '.auths | to_entries[] | .value.email')
      local repo_list=$(appClusterKubectl get secret $dcSecret --output='jsonpath={.metadata.annotations.paas\.ex\.anz\.com/repositories}' | tr -s '[:blank:][:space:]' ',,')
      local password_file=$(tempFile ${dcSecret}.passwd)
      appClusterKubectl get secret $dcSecret --output='jsonpath={.data.\.dockerconfigjson}' | base64 --decode | jq -Mr '.auths | to_entries[] | .value.password' > $password_file
      local sec_name=$(echo "${_APP_CLUSTER}-${dcSecret}" | tr -s '[:punct:]' '-')

      echo
      echo "About to create dockerconfigjson secret '$sec_name' in $_EX_CLUSTER cluster"
      local ex_secret_file=$(tempFile ex-secret)
      exClusterKubectl create secret generic "$sec_name" \
        --from-file=password="$password_file" \
        --from-literal=server="$docker_server" \
        --from-literal=email="$email" \
        --from-literal=repositories="$repo_list" \
        --dry-run -o yaml \
        | yq w - 'metadata.labels.app-cluster' "$_APP_CLUSTER" \
        | yq w - 'metadata.labels.secret' "$dcSecret" \
        | yq w - 'metadata.labels.type' "dockerconfigjson" \
        | yq w - 'metadata.labels.[paas.ex.anz.com/app-cluster]' "$_APP_CLUSTER" \
        | yq w - 'metadata.labels.[paas.ex.anz.com/type]' "dockerconfigjson" \
        | yq w - 'metadata.labels.[paas.ex.anz.com/secret-name]' "$dcSecret" \
        > $ex_secret_file

      # validate the config file
      kubeval $ex_secret_file

      exClusterKubectl apply -f $ex_secret_file
    done
  fi
}

function invokeHalyardAppConfigScript() {

  if ! local halyard_pod_name=$(exClusterKubectl get po \
            -l component=halyard,statefulset.kubernetes.io/pod-name \
            --field-selector status.phase=Running \
            -o jsonpath="{.items[0].metadata.name}"); then
    echo "Halyard not running !!!!"
    exit 1
  fi

  echo "Executing halyard-app-config.sh in $halyard_pod_name"
  exClusterKubectl exec $halyard_pod_name -- bash /home/spinnaker/halyard-app-config.sh
}

set +x
getKubeContext
createAppServiceAccount
createAppKubeConfigInExCluster
createDockerConfigSecretInExCluster
invokeHalyardAppConfigScript
