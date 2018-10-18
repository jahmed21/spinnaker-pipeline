#!/usr/bin/env bash

set -eo pipefail

declare -A _OPTS=(
 ["pipeline-template:"]="Template filepath to be published"
   ["template-config:"]="Template Config filepath"
         ["x509-cert:"]="X509 Certificate filepath (default to X509_CERT_FILE environment variable)"
          ["x509-key:"]="X509 Key filepath (default to X509_KEY_FILE environment variable)"
     ["spinnaker-api:"]="Spinnaker gate service URL (default to SPINNAKER_API environment variable)"
      ["kubectl-proxy"]="Use kubectl as proxy for connecting to spinnaker gate service"
  )

function usage() {
  echo
  echo "usage $(basename $0)  --app-name name --template-config path [--x509-cert-path path] [--x509-key-path path] [--spinnaker-api url] -- command"
  echo "usage $(basename $0)  --pipeline-template path [--x509-cert-path path] [--x509-key-path path] [--spinnaker-api url] -- command"
  for opt in "${!_OPTS[@]}"; do
    local pname=$(echo "$opt" | tr -d ':')
    printf "  %-25s %s\n" "--${pname}" "${_OPTS[$opt]}"
  done
  exit 1
}

_LONG_OPTS=$(echo "${!_OPTS[@]}" | tr ' ' ',')

# Process command line arguments
_TEMP=$(getopt -o h --long $_LONG_OPTS -n 'roer.sh' -- "$@")
if [ $? != 0 ] ; then 
   echo "Terminating..." >&2 
   exit 2
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$_TEMP"

TEMPLATE_CONFIG=""
PIPELINE_TEMPLATE=""
KUBECTL_PROXY=false

while true ; do
	case "$1" in
    --pipeline-template) PIPELINE_TEMPLATE=$2; _RUN_WITH_PARAM=true; shift 2;;
    --template-config) TEMPLATE_CONFIG=$2; _RUN_WITH_PARAM=true; shift 2;;
    --x509-cert) X509_CERT_FILE=$2; _RUN_WITH_PARAM=true; shift 2;;
    --x509-key) X509_KEY_FILE=$2; _RUN_WITH_PARAM=true; shift 2;;
    --spinnaker-api) SPINNAKER_API=$2; _RUN_WITH_PARAM=true; shift 2;;
    --kubectl-proxy) KUBECTL_PROXY=true; shift;;
	  --) shift ; break ;;
    *) echo "Internal error"; usage;;
	esac
done

if [[ -z "$X509_CERT_FILE" || -z "$X509_KEY_FILE" ]] || [[ ! $KUBECTL_PROXY && -z "$SPINNAKER_API" ]]; then
  echo "Error. Invalid x509 cert file '$X509_CERT_FILE' or  key file '$X509_KEY_FILE' or spinnaker api '$SPINNAKER_API'. Either pass as param or set environment variable"
  usage
fi

# Done processing command line arguments

function getCredential() { 
  # This tries to read environment variables. If not set, it grabs from gcloud
  local cluster=${CLOUDSDK_CONTAINER_CLUSTER:-$(gcloud config get-value container/cluster 2> /dev/null)}
  local region=${CLOUDSDK_COMPUTE_REGION:-$(gcloud config get-value compute/region 2> /dev/null)}
  local zone=${CLOUDSDK_COMPUTE_ZONE:-$(gcloud config get-value compute/zone 2> /dev/null)}
  local project=${GCLOUD_PROJECT:-$(gcloud config get-value core/project 2> /dev/null)}

  [[ -z "$cluster" || -z "$project" ]] && return 0

  if [ -n "$region" ]; then
    echo "Running: gcloud beta container clusters get-credentials --project=\"$project\" --region=\"$region\" \"$cluster\""
    gcloud beta container clusters get-credentials --project="$project" --region="$region" "$cluster" 
  else
    echo "Running: gcloud container clusters get-credentials --project=\"$project\" --zone=\"$zone\" \"$cluster\""
    gcloud container clusters get-credentials --project="$project" --zone="$zone" "$cluster" 
  fi
}

function checkRoerAuth() {

  if [[ $KUBECTL_PROXY ]]; then
    local gate_pod=$(kubectl get pods --namespace spinnaker -l "cluster=spin-gate" -o jsonpath="{.items[0].metadata.name}")
    if [[ -z "$gate_pod" ]]; then
      echo "Error. Unable to find gate pod for kubectl port forwarding"
      exit 1
    fi
    echo
    echo "Kubectl port-forward  8085 -> $gate_pod:8085"
    kubectl port-forward --namespace spinnaker $gate_pod 8085 >/dev/null &
    SPINNAKER_API=https://localhost:8085/
  fi

  export SPINNAKER_API

  declare -i cntr=6
  while ((cntr--)); do
    if $ROER_COMMAND app get spin >/dev/null 2>&1; then
      break
    fi
    sleep 10
  done

  if [[ $cntr -lt 0 ]]; then
    echo "Error. Invalid Cert/key/api-url. Unable to invoke roer"
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

  local localpath=${PWD}/$(basename $path)
  gsutil -q cp $path $localpath
  echo $localpath
}


function createAppIfNotExist() {
  local appName=$1

  if [[ -z "$appName" ]]; then
    echo "Error. Invalid parameter. appName(\$1) is mandatory" >&2
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

    echo
    echo "Creating app '$appName' using template "
    cat $template_file
    $ROER_COMMAND app create $appName $template_file
  else
    echo
    echo "App '$appName' already exists"
  fi
}

function publishPipelineTemplate() {
  local template_file=$1

  echo
  echo "Publish pipeline template '$template_file'"
  $ROER_COMMAND pipeline-template publish $template_file
}

function savePipeline() {
  local configFile=$1
  local appName=$(yq r $configFile pipeline.application)
  local pipelineName=$(yq r $configFile pipeline.name)

  echo
  echo "Validating config file '$configFile'"
  $ROER_COMMAND pipeline-template plan $configFile

  echo
  echo "Saving pipeline '$pipelineName' for app '$appName' from '$configFile'"
  $ROER_COMMAND pipeline save $configFile

  echo
  echo "Pipeline '$pipelineName', Id: $(getPipelineId "$appName" "$pipelineName")"
  getPipelineJSON "$appName" "$pipelineName" | jq -M .
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
X509_CERT_FILE=$(makeLocalCopyIfRequired $X509_CERT_FILE)
X509_KEY_FILE=$(makeLocalCopyIfRequired $X509_KEY_FILE)
ROER_COMMAND="roer --certPath $X509_CERT_FILE --keyPath $X509_KEY_FILE"

# Get GKE credential if specified
getCredential

# test roer connectivity and cert
checkRoerAuth

if [[ ! -z "$TEMPLATE_CONFIG" ]]; then
  createAppIfNotExist "$(yq r $TEMPLATE_CONFIG pipeline.application)"
  savePipeline $TEMPLATE_CONFIG
fi

if [[ ! -z "$PIPELINE_TEMPLATE" ]]; then
  publishPipelineTemplate  $PIPELINE_TEMPLATE
fi

if [[ ! -z "$@" ]]; then
  # Export variable and functions for subshell
  export TEMPLATE_CONFIG
  export PIPELINE_TEMPLATE
  export ROER_COMMAND
  declare -f -x createAppIfNotExist
  declare -f -x publishPipelineTemplate
  declare -f -x savePipeline
  declare -f -x getPipelineId
  declare -f -x getPipelineJSON
  declare -f -x getApplication

  echo
  echo "Running commands passed as argument [$@]"
  bash -c "$@"
fi
