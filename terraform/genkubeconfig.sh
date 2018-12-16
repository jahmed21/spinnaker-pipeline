#!/usr/bin/env bash
set -eo pipefail

declare -A _OPTS=(
          ["sa-name:"]="Service Account Name (default to spin-sa)"
     ["sa-namespace:"]="Service Account Namespace (default to default)"
  ["kubeconfig-file:"]="kubeconfig file name (default to kubeconfig)"
          ["cluster:"]="GKE cluster name"
             ["zone:"]="GKE cluster zone"
          ["project:"]="GCP Project Id"
  )

function usage() {

  echo
  echo "usage $(basename $0)  [--kubeconfig-file outfilename --sa-name name --sa-namespace ns]"

  for opt in "${!_OPTS[@]}"; do
    local pname=$(echo "$opt" | tr -d ':')
    printf "  %-25s %s\n" "--${pname}" "${_OPTS[$opt]}"
  done
  exit 1
}

_LONG_OPTS=$(echo "${!_OPTS[@]}" | tr ' ' ',')

# Process command line arguments
_TEMP=$(getopt -o h --long $_LONG_OPTS -n 'spin-cli.sh' -- "$@")
if [ $? != 0 ] ; then 
   echo "Terminating..." >&2 
   exit 2
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$_TEMP"

KUBECONFIG=""
SA_NAME="spin-sa"
SA_NAMESPACE="default"
CLUSTER=""
ZONE=""
PROJECT=""

while true ; do
	case "$1" in
    --kubeconfig-file) KUBECONFIG=$2; shift 2;;
    --sa-name) SA_NAME=$2; shift 2;;
    --sa-namespace) SA_NAMESPACE=$2; shift 2;;
    --cluster) CLUSTER=$2; shift 2;;
    --zone) ZONE=$2; shift 2;;
    --project) PROJECT=$2; shift 2;;
	  --) shift ; break ;;
    *) echo "Internal error"; usage;;
	esac
done

echo $CLUSTER
echo $ZONE
echo $PROJECT

if [[ -z "$CLUSTER" || -z "$ZONE" || -z "$PROJECT" || ! -z "$*" ]]; then
  usage
fi

if [[ -z "$KUBECONFIG" ]]; then
  KUBECONFIG="${CLUSTER}.kubeconfig"
fi

# Done processing command line arguments

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/$0.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function log() {
  >&2 echo
  >&2 echo "$(date): $@"
}

function getCredential() {
  [[ -z "$CLUSTER" || -z "$PROJECT" ]] && return 1

  log "Running: gcloud container clusters get-credentials --project=\"$PROJECT\" --zone=\"$ZONE\" \"$CLUSTER\""
  gcloud container clusters get-credentials --project="$PROJECT" --zone="$ZONE" "$CLUSTER"
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

function createLocalServiceAccount() {
  local sa_name=$1
  local sa_namespace=$2

  log "Creating service account '$sa_name' in '$sa_namespace' namespace"
  local file=$(tempFile app-sa)
  cat <<EOF_KUBECTL > $file
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    paas.ex.anz.com/cluster: ${CLUSTER}
    paas.ex.anz.com/project: ${PROJECT}
  name: ${sa_name}
  namespace: ${sa_namespace}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    paas.ex.anz.com/cluster: ${CLUSTER}
    paas.ex.anz.com/project: ${PROJECT}
  name: ${sa_name}-crb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: ${sa_name}
  namespace: ${sa_namespace}
EOF_KUBECTL

  # validate the config file
  kubeval $file

  kubectl -n $sa_namespace apply -f $file
}

# Create kubeconfig for spinnaker to connect to target app
function createKubeconfigForSA() {
  local kubeconfig_file=$1
  local sa_name=$2
  local sa_namespace=$3
  local secret=""

  if ! secret="$(kubectl -n $sa_namespace get serviceaccount $sa_name -o 'jsonpath={.secrets[0].name}' 2>/dev/null)"; then
    echo "Secret for serviceaccounts \"$sa_name\" not found." >&2
    exit 2
  fi

  if [[ -z "$secret" ]]; then
    echo "Secret for serviceaccounts \"$sa_name\" not found." >&2
    exit 2
  fi

  # ca crt
  local ca_crt="$(tempFile ca_crt)"
  kubectl -n $sa_namespace get secret "$secret" -o "jsonpath={.data.ca\.crt}" | base64 -d > $ca_crt

  # token
  local token="$(kubectl -n $sa_namespace get secret "$secret" -o "jsonpath={.data.token}" | base64 -d)"

  log "Creating kubeconfig with internal ip"
  local internal_kubeconfig=$(tempFile kubeconfig)
  export KUBECONFIG=$internal_kubeconfig

  gcloud container clusters get-credentials --internal-ip --project="$PROJECT" --zone="$ZONE" "$CLUSTER"
  cat $internal_kubeconfig

  log "Creating kubeconfig file with token"
  # context
  local context="$(kubectl config current-context)"

  # cluster
  local cluster="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"$context\")].context.cluster}")"
  local server="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"$cluster\")].cluster.server}")"

  kubectl --kubeconfig $kubeconfig_file config set-credentials "$sa_name" --token="$token"
  kubectl --kubeconfig $kubeconfig_file config set-cluster "$cluster" --server="$server" --certificate-authority="$ca_crt" --embed-certs
  kubectl --kubeconfig $kubeconfig_file config set-context "$sa_namespace" --cluster="$cluster" --namespace="$sa_namespace" --user="${sa_name}"
  kubectl --kubeconfig $kubeconfig_file config use-context "$sa_namespace"
}

function prepareKubeconfig() {
  local kubeconfig_file=$1
  local sa_name=$2
  local sa_namespace=$3

  log "Preparing kubeconfig for SA '$sa_namespace/$sa_name'; generated file '$kubeconfig_file'"

  if [[ -z "$(kubectl -n $sa_namespace get serviceaccount $sa_name -o=jsonpath='{.metadata.name}' 2>/dev/null)" ]]; then
    createLocalServiceAccount $sa_name $sa_namespace
  else
    log "Service account $sa_name already present.."
  fi

  createKubeconfigForSA $kubeconfig_file $sa_name $sa_namespace
}

getCredential
prepareKubeconfig  $KUBECONFIG $SA_NAME $SA_NAMESPACE
