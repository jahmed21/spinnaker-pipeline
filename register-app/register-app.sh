#!/usr/bin/env bash

set -eo pipefail
set +x

# Process command line arguments
function usage() {
echo
cat <<EOF
usage $(basename $0)
  --spin-project-id Project Id of the Spinnaker deployment project
  --spin-cluster    Spinnaker GKE Cluster name
  --spin-namespace  k8s namespace where spinnaker is deployed (default to 'spinnaker')
  --app-project-id  Project Id of the Application to be integrated with Spinnaker
  --app-cluster     Application GKE Cluster name
  --sa-name         Name of the service account to be created in Application GKE for spinnaker to connect and deploy (default to 'ex-spinnaker')
  --region          GCP Region (default to 'australia-southeast1')
  --bucket          URL of the GCS Bucket for which notification needs to be enabled
  --publish-topic   Name of the topic where GCS notification will be sent
EOF
exit 1
}

TEMP=$(getopt -o h --long spin-cluster:,spin-project-id:,spin-namespace:,app-cluster:,app-project-id:,region:,sa-name:,bucket:,publish-topic: -n 'register-app.sh' -- "$@")

if [ $? != 0 ] ; then 
   echo "Terminating..." >&2 
   exit 2
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

_REGION="australia-southeast1"
_SPIN_CLUSTER=""
_SPIN_PROJECT_ID=""
_SPIN_NAMESPACE="spinnaker"
_APP_CLUSTER=""
_APP_PROJECT_ID=""
_APP_NAMESPACE="kube-system"
_APP_CLUSTER_SA_NAME="ex-spinnaker"
_BUCKET_URL=""
_PUBLISH_TOPIC=""

_APP_CLUSTER_KUBECONTEXT=""
_SPIN_CLUSTER_KUBECONTEXT=""

while true ; do
	case "$1" in
    --spin-cluster) _SPIN_CLUSTER=$2; shift 2;;
    --spin-project-id) _SPIN_PROJECT_ID=$2; shift 2;;
    --app-cluster) _APP_CLUSTER=$2; shift 2;;
    --app-project-id) _APP_PROJECT_ID=$2; shift 2;;
    --region) _REGION=$2; shift 2;;
    --sa-name) _APP_CLUSTER_SA_NAME=$2; shift 2;;
    --bucket) _BUCKET_URL=$2 ; shift 2 ;;
    --publish-topic) _PUBLISH_TOPIC=$2 ; shift 2 ;;
	  --) shift ; break ;;
	  *) echo "Internal error!" ; usage ;;
	esac
done

if [[ ! -z "$*" \
      || -z "${_SPIN_CLUSTER}" \
      || -z "${_SPIN_PROJECT_ID}" \
      || -z "${_APP_CLUSTER}" \
      || -z "${_APP_PROJECT_ID}" \
      ]]; then
  usage
fi

# Done processing command line arguments
echo
echo "---------------- Parameters ------------------"
echo "               Region: $_REGION"
echo "  Spinnaker ProjectId: $_SPIN_PROJECT_ID"
echo "    Spinnaker Cluster: $_SPIN_CLUSTER"
echo "  Spinnaker Namespace: $_SPIN_NAMESPACE"
echo "Application ProjectId: $_APP_PROJECT_ID"
echo "  Application Cluster: $_APP_CLUSTER"
echo "  Application SA Name: $_APP_CLUSTER_SA_NAME"
echo "           Bucket URL: $_BUCKET_URL"
echo "        Publish Topic: $_PUBLISH_TOPIC"
echo

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/register-app.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function echoAndExec() {
  echo "$@"
  eval "$@"
}

function getKubeContext() {
    echo
    echo "Getting kubeconfig for $_APP_CLUSTER cluster"
    gcloud container clusters get-credentials ${_APP_CLUSTER} --region ${_REGION} --project ${_APP_PROJECT_ID}
    _APP_CLUSTER_KUBECONTEXT=$(kubectl config current-context)
    echo "Context: $_APP_CLUSTER_KUBECONTEXT"

    echo
    echo "Getting kubeconfig for $_SPIN_CLUSTER cluster"
    gcloud container clusters get-credentials ${_SPIN_CLUSTER} --region ${_REGION} --project ${_SPIN_PROJECT_ID}
    _SPIN_CLUSTER_KUBECONTEXT=$(kubectl config current-context)
    echo "Context: $_SPIN_CLUSTER_KUBECONTEXT"
}

function appClusterKubectl() {
  kubectl --context "$_APP_CLUSTER_KUBECONTEXT" --namespace "$_APP_NAMESPACE" $@
}

function spinClusterKubectl() {
  kubectl --context "$_SPIN_CLUSTER_KUBECONTEXT" --namespace "$_SPIN_NAMESPACE" $@
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
    paas.ex.anz.com/cluster: ${_SPIN_CLUSTER}
    paas.ex.anz.com/project: ${_SPIN_PROJECT_ID}
  name: ${_APP_CLUSTER_SA_NAME}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    paas.ex.anz.com/cluster: ${_SPIN_CLUSTER}
    paas.ex.anz.com/project: ${_SPIN_PROJECT_ID}
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
function createKubeConfigInSpinCluster() {
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

  local sec_name=$(echo "${_APP_PROJECT_ID}-${_APP_CLUSTER}-kubeconfig" | tr -s '[:punct:]' '-')
  echo
  echo "About to create kubeconfig secret '$sec_name' in $_SPIN_PROJECT_ID $_SPIN_CLUSTER cluster"

  # cluster
  local cluster="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"$context\")].context.cluster}")"
  local server="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"$cluster\")].cluster.server}")"
  local ca_crt="$(tempFile ca_crt)"
  appClusterKubectl get secret "$secret" -o "jsonpath={.data.ca\.crt}" | openssl enc -d -base64 -A > $ca_crt

  # token
  local token="$(appClusterKubectl get secret "$secret" -o "jsonpath={.data.token}" | openssl enc -d -base64 -A)"
  local namespace="default"
  local kubeconfig_file="$(tempFile kubeconfig)"
  local spin_secret_file=$(tempFile spin-kubeconfig)

  kubectl --kubeconfig $kubeconfig_file config set-credentials "$_APP_CLUSTER_SA_NAME" --token="$token"
  kubectl --kubeconfig $kubeconfig_file config set-cluster "$cluster" --server="$server" --certificate-authority="$ca_crt" --embed-certs
  kubectl --kubeconfig $kubeconfig_file config set-context "$namespace" --cluster="$cluster" --namespace="$namespace" --user="${_APP_CLUSTER_SA_NAME}"
  kubectl --kubeconfig $kubeconfig_file config use-context "$namespace"
  kubectl --kubeconfig $kubeconfig_file cluster-info > /dev/null

  spinClusterKubectl create secret generic "$sec_name" \
    --from-file=kubeconfig="$kubeconfig_file" \
    --dry-run -o yaml \
    | yq w - 'metadata.labels.[paas.ex.anz.com/cluster]' "$_APP_CLUSTER" \
    | yq w - 'metadata.labels.[paas.ex.anz.com/project]' "$_APP_PROJECT_ID" \
    | yq w - 'metadata.labels.[paas.ex.anz.com/type]' "kubeconfig" \
    > $spin_secret_file

  # validate the config file
  kubeval $spin_secret_file

  spinClusterKubectl apply -f $spin_secret_file
}

function getDockerConfigSecretNameFromAppCluster() {
  appClusterKubectl get secret \
      --field-selector type=kubernetes.io/dockerconfigjson \
      --selector paas.ex.anz.com/project=${_SPIN_PROJECT_ID},paas.ex.anz.com/cluster=${_SPIN_CLUSTER} \
      -o=jsonpath='{.items[*].metadata.name}'
}

function createDockerConfigSecretInSpinCluster() {
  local hcScript=$(tempFile  halyard-config)

  if local secretList="$(getDockerConfigSecretNameFromAppCluster)"; then
    for dcSecret in $secretList
    do
      local docker_server=$(appClusterKubectl get secret $dcSecret --output='jsonpath={.data.\.dockerconfigjson}' | base64 --decode | jq -Mr '.auths | to_entries[] | .key')
      local email=$(appClusterKubectl get secret $dcSecret --output='jsonpath={.data.\.dockerconfigjson}' | base64 --decode | jq -Mr '.auths | to_entries[] | .value.email')
      local repo_list=$(appClusterKubectl get secret $dcSecret --output='jsonpath={.metadata.annotations.paas\.ex\.anz\.com/repositories}' | tr -s '[:blank:][:space:]' ',,')
      local bucket=$(appClusterKubectl get secret $dcSecret --output='jsonpath={.metadata.annotations.paas\.ex\.anz\.com/bucket}')
      local password_file=$(tempFile ${dcSecret}.passwd)
      appClusterKubectl get secret $dcSecret --output='jsonpath={.data.\.dockerconfigjson}' | base64 --decode | jq -Mr '.auths | to_entries[] | .value.password' > $password_file
      local sec_name=$(echo "${_APP_PROJECT_ID}-${_APP_CLUSTER}-${dcSecret}" | tr -s '[:punct:]' '-')

      echo
      echo "About to create dockerconfigjson secret '$sec_name' in $_SPIN_CLUSTER cluster"
      local spin_secret_file=$(tempFile spin-secret)
      spinClusterKubectl create secret generic "$sec_name" \
        --from-file=password="$password_file" \
        --from-literal=server="$docker_server" \
        --from-literal=email="$email" \
        --from-literal=repositories="$repo_list" \
        --from-literal=bucket="$bucket" \
        --dry-run -o yaml \
        | yq w - 'metadata.labels.[paas.ex.anz.com/cluster]' "$_APP_CLUSTER" \
        | yq w - 'metadata.labels.[paas.ex.anz.com/project]' "$_APP_PROJECT_ID" \
        | yq w - 'metadata.labels.[paas.ex.anz.com/type]' "dockerconfigjson" \
        | yq w - 'metadata.labels.[paas.ex.anz.com/secret-name]' "$dcSecret" \
        > $spin_secret_file

      # validate the config file
      kubeval $spin_secret_file

      spinClusterKubectl apply -f $spin_secret_file
    done
  fi
}

function setupPublisher() {
  if [[ -z "$_BUCKET_URL" || -z "$_PUBLISH_TOPIC" ]]; then
    echo "Publisher not enabled"
    return 0
  fi

  echo "GCS notification setup..."
  echoAndExec gsutil notification create -p ${_APP_PROJECT_ID} -f json -t projects/${_SPIN_PROJECT_ID}/topics/${_PUBLISH_TOPIC}  ${_BUCKET_URL}
}

function invokeHalyardAppConfigScript() {

  if ! local halyard_pod_name=$(spinClusterKubectl get po \
            -l component=halyard,statefulset.kubernetes.io/pod-name \
            --field-selector status.phase=Running \
            -o jsonpath="{.items[0].metadata.name}"); then
    echo "Halyard not running !!!!"
    exit 1
  fi

  echo
  echo
  echo
  echo "Executing halyard-app-config.sh in $halyard_pod_name"
  echo
  spinClusterKubectl exec $halyard_pod_name -- bash /opt/halyard/additionalConfigMaps/halyard-app-config.sh
}

set +x
getKubeContext
createAppServiceAccount
setupPublisher
createKubeConfigInSpinCluster
createDockerConfigSecretInSpinCluster
invokeHalyardAppConfigScript
