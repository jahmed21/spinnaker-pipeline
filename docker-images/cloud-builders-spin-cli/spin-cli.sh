#!/usr/bin/env bash

set -eo pipefail

declare -A _OPTS=(
 ["pipeline-template:"]="Template filepath to be published"
   ["template-config:"]="Template Config filepath"
   ["spin-kubeconfig:"]="Kubeconfig file for connecting to spinnaker"
           ["sa-name:"]="Service Account Name"
      ["sa-namespace:"]="Service Account Namespace (defualt to 'default' namespace)"
   ["manifest-bucket:"]="Manifest bucket name"
        ["spin-topic:"]="Spinnaker Topic Name"
         ["x509-cert:"]="X509 Certificate filepath (default to X509_CERT_FILE environment variable)"
          ["x509-key:"]="X509 Key filepath (default to X509_KEY_FILE environment variable)"
     ["spinnaker-api:"]="Spinnaker gate service URL (default to SPINNAKER_API environment variable)"
      ["kubectl-proxy"]="Use kubectl as proxy for connecting to spinnaker gate service"
  )

function usage() {

  echo
  echo "usage $(basename $0)  --template-config path [--x509-cert-path path] [--x509-key-path path] [--spinnaker-api url] -- command"
  echo "usage $(basename $0)  --pipeline-template path [--x509-cert-path path] [--x509-key-path path] [--spinnaker-api url] -- command"
  echo "usage $(basename $0)  --spin-kubeconfig path --sa-name name --sa-namespace ns -- command"
  echo "usage $(basename $0)  --spin-kubeconfig path --sa-name name --sa-namespace ns --manifest-bucket name --spin-topic name -- command"

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

TEMPLATE_CONFIG=""
PIPELINE_TEMPLATE=""
SPIN_KUBECONFIG=""
SA_NAME=""
SA_NAMESPACE="default"
BUCKET=""
TOPIC=""
KUBECTL_PROXY=false

while true ; do
	case "$1" in
    --pipeline-template) PIPELINE_TEMPLATE=$2; shift 2;;
    --template-config) TEMPLATE_CONFIG=$2; shift 2;;
    --spin-kubeconfig) SPIN_KUBECONFIG=$2; shift 2;;
    --sa-name) SA_NAME=$2; shift 2;;
    --sa-namespace) SA_NAMESPACE=$2; shift 2;;
    --manifest-bucket) BUCKET=$2; shift 2;;
    --spin-topic) TOPIC=$2; shift 2;;
    --x509-cert) X509_CERT_FILE=$2; shift 2;;
    --x509-key) X509_KEY_FILE=$2; shift 2;;
    --spinnaker-api) SPINNAKER_API=$2; shift 2;;
    --kubectl-proxy) KUBECTL_PROXY=true; shift;;
	  --) shift ; break ;;
    *) echo "Internal error"; usage;;
	esac
done

MODE_PUBLISH=false
MODE_CONFIG=false
MODE_REGISTER=false

# Validate the parameters

if [[ ! -z "$PIPELINE_TEMPLATE" ]]; then

  MODE_PUBLISH=true
  #  Input validation for Template publish mode.

  if [[ -z "$X509_CERT_FILE" || -z "$X509_KEY_FILE" ]] || [[ ! $KUBECTL_PROXY && -z "$SPINNAKER_API" ]]; then
    echo "Error. Invalid x509 cert file '$X509_CERT_FILE' or  key file '$X509_KEY_FILE' or spinnaker api '$SPINNAKER_API'. Either pass as param or set environment variable"
    usage
  fi

elif [[ ! -z "$TEMPLATE_CONFIG" ]]; then

  MODE_CONFIG=true

  #  Input validation for Pipeline create/update mode.

  if [[ -z "$X509_CERT_FILE" || -z "$X509_KEY_FILE" ]] || [[ ! $KUBECTL_PROXY && -z "$SPINNAKER_API" ]]; then
    echo "Error. Invalid x509 cert file '$X509_CERT_FILE' or  key file '$X509_KEY_FILE' or spinnaker api '$SPINNAKER_API'. Either pass as param or set environment variable"
    usage
  fi

elif [[ ! -z "$SPIN_KUBECONFIG" ]]; then

  MODE_REGISTER=true

  #  Input validation for publishing kubeconfig
  if [[ -z "$SA_NAME" || -z "$CLOUDSDK_CONTAINER_CLUSTER" || -z "$CLOUDSDK_COMPUTE_REGION"  || -z "$GCLOUD_PROJECT" ]]; then
    echo "Error. Invalid SA name '$SA_NAME' or CLOUDSDK_CONTAINER_CLUSTER '$CLOUDSDK_CONTAINER_CLUSTER' or CLOUDSDK_COMPUTE_REGION '$CLOUDSDK_COMPUTE_REGION' or GCLOUD_PROJECT '$GCLOUD_PROJECT'"
    usage
  fi

elif [[ -z "$*" ]]; then

  usage

fi

# Done processing command line arguments

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/spin-cli.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function log() {
  >&2 echo
  >&2 echo "$(date): $@"
}

function createKubectlProxy() {
  # Get local GKE credential
  getCredential

  local gate_pod=$(kubectl get pods --namespace spinnaker -l "cluster=spin-gate" -o jsonpath="{.items[0].metadata.name}")
  if [[ -z "$gate_pod" ]]; then
    log "Error. Unable to find gate pod for kubectl port forwarding"
    exit 1
  fi
  log "Kubectl port-forward  8085 -> $gate_pod:8085"
  kubectl port-forward --namespace spinnaker $gate_pod 8085 >/dev/null &
  export SPINNAKER_API=https://localhost:8085/
}

function checkRoerAuth() {
  log "Checking roer connectivity and auth"

  X509_CERT_FILE=$(makeLocalCopyIfRequired $X509_CERT_FILE)
  X509_KEY_FILE=$(makeLocalCopyIfRequired $X509_KEY_FILE)
  ROER_COMMAND="roer --certPath $X509_CERT_FILE --keyPath $X509_KEY_FILE"

  declare -i cntr=6
  while ((cntr--)); do
    if $ROER_COMMAND app get spin >/dev/null 2>&1; then
      break
    fi
    log "Unable to connect to gate api... $cntr. Retry after 10 seconds"
    sleep 10
  done

  if [[ $cntr -lt 0 ]]; then
    log "Error. Invalid Cert/key/api-url. Unable to invoke roer"
    set -x
    $ROER_COMMAND app get spin
    exit 1
  fi
}

function makeLocalCopyIfRequired() {
  local path="$1"

  if ! echo "$path" | grep "^gs://" >/dev/null 2>&1; then
    echo "$path"
    return 0
  fi

  local localpath=$(tempFile $(basename "$path"))
  log "Getting local copy for $path -> $localpath"
  gsutil -q cp $path $localpath
  echo $localpath
}


function createAppIfNotExist() {
  local appName=$1

  if [[ -z "$appName" ]]; then
    log "Error. Invalid parameter. appName(\$1) is mandatory" >&2
    return 1
  fi

  if ! $ROER_COMMAND app get "$appName" >/dev/null 2>&1; then
    local template_file="${2:-app.yml}"
    if [[ ! -f $template_file ]]; then
      template_file=/builder/app.yml
    fi
    local email="${3:-${appName}@gcp.anz.com}"
    yq w -i $template_file email  "$email"
    yq w -i $template_file attributes.email  "$email"
    yq w -i $template_file attributes.updateTs $(date +%s000)  
    yq w -i $template_file attributes.createTs $(date +%s000)  

    log "Creating app '$appName' using template "
    cat $template_file
    $ROER_COMMAND app create $appName $template_file
  else
    log "App '$appName' already exists"
  fi
}

function publishPipelineTemplate() {
  local template_file=$1
  log "Publish pipeline template '$template_file'"

  if [[ $KUBECTL_PROXY ]]; then
    createKubectlProxy
  fi

  checkRoerAuth

  log "Publishing to server using roer"
  $ROER_COMMAND pipeline-template publish $template_file
}

function savePipeline() {
  local configFile=$1
  log "Create or Update pipeline from '$configFile'"

  local appName=$(yq r $configFile pipeline.application)
  local pipelineName=$(yq r $configFile pipeline.name)

  if [[ $KUBECTL_PROXY ]]; then
    createKubectlProxy
  fi

  checkRoerAuth

  createAppIfNotExist "$appName"

  log "Validating config file '$configFile'"
  $ROER_COMMAND pipeline-template plan $configFile

  log "Saving pipeline '$pipelineName' for app '$appName' from '$configFile'"
  $ROER_COMMAND pipeline save $configFile

  log "Pipeline '$pipelineName', Id: $(getPipelineId "$appName" "$pipelineName")"
  getPipelineJSON "$appName" "$pipelineName" | jq -M .
}

function getCredential() {
  # This tries to read environment variables. If not set, it grabs from gcloud
  local cluster=${CLOUDSDK_CONTAINER_CLUSTER:-$(gcloud config get-value container/cluster 2> /dev/null)}
  local region=${CLOUDSDK_COMPUTE_REGION:-$(gcloud config get-value compute/region 2> /dev/null)}
  local zone=${CLOUDSDK_COMPUTE_ZONE:-$(gcloud config get-value compute/zone 2> /dev/null)}
  local project=${GCLOUD_PROJECT:-$(gcloud config get-value core/project 2> /dev/null)}

  [[ -z "$cluster" || -z "$project" ]] && return 1

  if [ -n "$region" ]; then
    log "Running: gcloud beta container clusters get-credentials --project=\"$project\" --region=\"$region\" \"$cluster\""
    gcloud beta container clusters get-credentials --project="$project" --region="$region" "$cluster"
  else
    log "Running: gcloud container clusters get-credentials --project=\"$project\" --zone=\"$zone\" \"$cluster\""
    gcloud container clusters get-credentials --project="$project" --zone="$zone" "$cluster"
  fi
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
    paas.ex.anz.com/cluster: ${CLOUDSDK_CONTAINER_CLUSTER}
    paas.ex.anz.com/project: ${GCLOUD_PROJECT}
  name: ${sa_name}
  namespace: ${sa_namespace}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    paas.ex.anz.com/cluster: ${CLOUDSDK_CONTAINER_CLUSTER}
    paas.ex.anz.com/project: ${GCLOUD_PROJECT}
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

  log "Creating kubeconfig file with token"

  # context
  local context="$(kubectl config current-context)"

  # cluster
  local cluster="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"$context\")].context.cluster}")"
  local server="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"$cluster\")].cluster.server}")"
  local ca_crt="$(tempFile ca_crt)"
  kubectl -n $sa_namespace get secret "$secret" -o "jsonpath={.data.ca\.crt}" | base64 -d > $ca_crt

  # token
  local token="$(kubectl -n $sa_namespace get secret "$secret" -o "jsonpath={.data.token}" | base64 -d)"

  kubectl --kubeconfig $kubeconfig_file config set-credentials "$sa_name" --token="$token"
  kubectl --kubeconfig $kubeconfig_file config set-cluster "$cluster" --server="$server" --certificate-authority="$ca_crt" --embed-certs
  kubectl --kubeconfig $kubeconfig_file config set-context "$sa_namespace" --cluster="$cluster" --namespace="$sa_namespace" --user="${sa_name}"
  kubectl --kubeconfig $kubeconfig_file config use-context "$sa_namespace"
}

function registerKubeconfigFile() {
  local spin_kubeconfig=$1
  local app_kubeconfig=$2
  local sec_name=$(echo "${CLOUDSDK_CONTAINER_CLUSTER}-kubeconfig" | tr -s '[:punct:]' '-')
  local spin_secret_file="$(tempFile spin-secret)"

  log "Creating secret '$sec_name' for  $app_kubeconfig in $spin_kubeconfig"

  spin_kubeconfig=$(makeLocalCopyIfRequired ${spin_kubeconfig})

  kubectl --kubeconfig $spin_kubeconfig create secret generic "$sec_name" \
    --from-file=kubeconfig="$app_kubeconfig" \
    --dry-run -o yaml \
    | yq w - 'metadata.labels.[paas.ex.anz.com/cluster]' "$CLOUDSDK_CONTAINER_CLUSTER" \
    | yq w - 'metadata.labels.[paas.ex.anz.com/project]' "$GCLOUD_PROJECT" \
    | yq w - 'metadata.labels.[paas.ex.anz.com/type]' "kubeconfig" \
    > $spin_secret_file

  # validate the config file
  kubeval $spin_secret_file

  kubectl --kubeconfig $spin_kubeconfig apply -f $spin_secret_file
}

function setupBucketNotification() {
  local bucket=$1
  local topic=$2

  log "GCS notification for bucket '$bucket' -> topic '$topic'"
  gsutil notification create -f json -t $topic  gs://${bucket}
}

function registerWithSpin() {
  local spin_kubeconfig=$1
  local sa_name=$2
  local sa_namespace=$3

  log "Register kubeconfig for SA '$sa_namespace/$sa_name' with spin using '$spin_kubeconfig'"

  # Get local GKE credential
  getCredential

  if [[ -z "$(kubectl -n $sa_namespace get serviceaccount $sa_name -o=jsonpath='{.metadata.name}' 2>/dev/null)" ]]; then
    createLocalServiceAccount $sa_name $sa_namespace
  else
    log "Service account $sa_name already present.."
  fi

  local app_kubeconfig="$(tempFile kubeconfig)"
  createKubeconfigForSA $app_kubeconfig $sa_name $sa_namespace

  registerKubeconfigFile $spin_kubeconfig $app_kubeconfig

  if [[ ! -z "${BUCKET}"  && ! -z "${TOPIC}" ]]; then
    setupBucketNotification $BUCKET $TOPIC
  fi
}

function getApplication() {
  local appName=$1
  $ROER_COMMAND app get "$appName" 2>/dev/null
}

function getPipelineJSON() {
  local appName=$1
  local pipelineName=$2
  $ROER_COMMAND pipeline get "$appName" "$pipelineName" 2>/dev/null
}

function getPipelineId() {
  local appName=$1
  local pipelineName=$2
  getPipelineJSON "$appName" "$pipelineName" | jq -Mr .id
}

# Main logic starts here

if [[ $MODE_CONFIG == true ]]; then
  savePipeline $TEMPLATE_CONFIG
fi

if [[ $MODE_PUBLISH == true ]]; then
  publishPipelineTemplate  $PIPELINE_TEMPLATE
fi

if [[ $MODE_REGISTER == true ]]; then
  registerWithSpin $SPIN_KUBECONFIG $SA_NAME $SA_NAMESPACE
fi

if [[ ! -z "$@" ]]; then
  # Export variable and functions for subshell
  export SPINNAKER_SPI
  export ROER_COMMAND="roer --certPath $X509_CERT_FILE --keyPath $X509_KEY_FILE"

  declare -f -x getCredential
  declare -f -x checkRoerAuth
  declare -f -x createKubectlProxy
  declare -f -x createAppIfNotExist
  declare -f -x makeLocalCopyIfRequired
  declare -f -x publishPipelineTemplate
  declare -f -x registerWithSpin
  declare -f -x createKubeconfigForSA
  declare -f -x registerKubeconfigFile
  declare -f -x setupBucketNotification
  declare -f -x savePipeline
  declare -f -x getPipelineId
  declare -f -x getPipelineJSON
  declare -f -x getApplication

  log "Running commands passed as argument [$@]"
  bash -c "$@"
fi
