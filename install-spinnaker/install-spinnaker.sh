#!/usr/bin/env bash

set +x
set -eo pipefail

# Process command line arguments
function usage() {
echo
cat <<EOF
usage $(basename $0) -prnisc
  -p | --project                Project Id of the Spinnaker deployment project
  -r | --helm-relase-name       Helm relase name
  -n | --namespace              Kubernetes namespace where spinnaker will be deployed
  -i | --oauth2-client-id       Google OAUTH2 client id
  -s | --oauth2-client-secret   Google OAUTH2 client secret
  -c | --clean                  Uninstall previous helm installation first
EOF
exit 1
}

TEMP=$(getopt -o p:r:n:i:s:c --long project:,helm-release-name:,namespace:,oauth2-client-id:,oauth2-client-secret:,clean -n 'example.bash' -- "$@")
if [ $? != 0 ] ; then 
   echo "Terminating..." >&2 
   exit 2
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

_CD_PROJECT_ID=""
_HELM_RELEASE_NAME=""
_SPINNAKER_NS=""
_OAUTH2_CLIENT_ID=""
_OAUTH2_CLIENT_SECRET=""
_OAUTH2_ENABLED=false
_UNINSTALL=false

while true ; do
	case "$1" in
    -p|--project) _CD_PROJECT_ID=$2; shift 2;;
    -r|--helm-release-name) _HELM_RELEASE_NAME=$2; shift 2;;
    -n|--namespace) _SPINNAKER_NS=$2; shift 2;;
    -i|--oauth2-client-id) _OAUTH2_CLIENT_ID=$2; shift 2;;
    -s|--oauth2-client-secret) _OAUTH2_CLIENT_SECRET=$2; shift 2;;
    -c|--clean) _UNINSTALL=true; shift ;;
	  --) shift ; break ;;
	  *) echo "Internal error!" ; usage ;;
	esac
done

if [[ ! -z "$*" || -z "$_CD_PROJECT_ID" ]]; then
   usage
fi

[[ -z "$_HELM_RELEASE_NAME" ]] && _HELM_RELEASE_NAME="${_CD_PROJECT_ID}-spin"
[[ -z "$_SPINNAKER_NS" ]] && _SPINNAKER_NS="spinnaker"
if [[ ! -z "$_OAUTH2_CLIENT_ID" && ! -z "$_OAUTH2_CLIENT_SECRET" ]]; then
  _OAUTH2_ENABLED=true
fi


echo "Parameters"
echo "_CD_PROJECT_ID: $_CD_PROJECT_ID"
echo "_HELM_RELEASE_NAME: $_HELM_RELEASE_NAME"
echo "_SPINNAKER_NS: $_SPINNAKER_NS"
echo "_OAUTH2_CLIENT_ID: $_OAUTH2_CLIENT_ID"
echo "_OAUTH2_CLIENT_SECRET: $_OAUTH2_CLIENT_SECRET"
echo "_OAUTH2_ENABLED: $_OAUTH2_ENABLED"
echo "_UNINSTALL: $_UNINSTALL"
echo

# Done processing command line arguments

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/install-spinnaker.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function uninstall() {
  echo
  echo "Cleaning up previous installation"
  helm --debug delete --purge  ${_HELM_RELEASE_NAME} --timeout 180 || true

  # delete jobs, pods, statefulsets, configmaps, secrets...etc
  kubectl --namespace ${_SPINNAKER_NS} --timeout 180s delete all --all || true
  
  # now delete the entire namesapce
  kubectl delete namespace ${_SPINNAKER_NS} --timeout 180s || true

  # now delete the CRB
  kubectl delete clusterrolebinding  "${_HELM_RELEASE_NAME}-spinnaker-spinnaker" || true

  # now delete the tillerless storage
  kubectl --namespace kube-system delete secret "${_HELM_RELEASE_NAME}.v1" || true

  # wait till spinnaker namespace removed
  while [[ ! -z "$(kubectl get namespace ${_SPINNAKER_NS}  -o=jsonpath='{.metadata.name}')" ]]; do
    sleep 3
  done
  echo "Done deleting previous installation"
}

function createAdditinoalConfigMap() {

  echo
  echo "Creating configmap for halyard additional config"
# Create the spinnaker namespace and additonal hal configmap configured in spinnaker helm chart

  local configmap_file=$(tempFile additional-config)
  cat <<EOF_KUBECTL > $configmap_file
apiVersion: v1
kind: Namespace
metadata:
  name: ${_SPINNAKER_NS}
spec:
  finalizers:
  - kubernetes
---
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    app: ${_HELM_RELEASE_NAME}-spinnaker
    release: ${_HELM_RELEASE_NAME}
  name: my-halyard-config
  namespace: ${_SPINNAKER_NS}
data:
  config.sh: |

    bash /opt/halyard/additional/halyard-additional-config.sh \
      "${_SPINNAKER_NS}" "${_OAUTH2_ENABLED}" "${_OAUTH2_CLIENT_ID}" "${_OAUTH2_CLIENT_SECRET}"
EOF_KUBECTL

  # Add halyard-additional-config script to configmap
  kubectl create configmap test-$$ --from-file=halyard-additional-config.sh --dry-run -o yaml \
    | yq r - 'data'  \
    | sed "s/^/  /" >> $configmap_file

  # Add halyard-additional-config script to configmap
  kubectl create configmap test-$$ --from-file=halyard-app-config.sh --dry-run -o yaml \
    | yq r - 'data'  \
    | sed "s/^/  /" >> $configmap_file

  # validate the config file
  kubeval $configmap_file

  kubectl apply -f $configmap_file
}

function invokeHelm() {
  echo
  echo "Get Spinnaker GCS Key"
  # Encode spinnaker GCS Key for sed to inject them in values.yaml
  JSON_KEY="$(gsutil cat gs://${_CD_PROJECT_ID}-halyard-config/spinnaker-gcs-access-key.json)"

  # Replace the placeholders in values.yaml
  cat values.yaml | yq w - 'gcs.jsonKey' "$JSON_KEY" | yq w - 'dockerRegistries.[0].password' "$JSON_KEY" > values-updated.yaml

  # Replace the placeholders in values.yaml
  echo
  echo "Helming now"
  set -x
  helm --debug upgrade --install ${_HELM_RELEASE_NAME} stable/spinnaker \
    --timeout 1200 \
    --wait \
    --namespace ${_SPINNAKER_NS} \
    --values values-updated.yaml \
    --set gcs.project=${_CD_PROJECT_ID},gcs.bucket=${_CD_PROJECT_ID}-spinnaker-config
}

# Main logic starts here

if [[ "${_UNINSTALL}" != "true" ]]; then
  helm status ${_HELM_RELEASE_NAME} || true
fi

if [[ "${_UNINSTALL}" == "true" || ! -z "$(helm status ${_HELM_RELEASE_NAME} | grep 'STATUS: \(FAILED\|PENDING\)' )" ]]; then
  uninstall
fi

createAdditinoalConfigMap

invokeHelm
