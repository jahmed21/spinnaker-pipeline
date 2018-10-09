#!/usr/bin/env bash

set +x
set -eo pipefail

function usage() {
echo
cat <<EOF
usage $(basename $0)
  --project                   Project Id of the Spinnaker deployment project
  --helm-relase-name          Helm relase name
  --namespace                 Kubernetes namespace where spinnaker will be deployed
  --oauth2-client-id          Google OAUTH2 client id
  --oauth2-client-secret      Google OAUTH2 client secret
  --pubsub-subscription       Name of the pubsub subscription to be used by spinnaker
  --clean                     Uninstall previous helm installation first
EOF
exit 1
}

# Process command line arguments
TEMP=$(getopt -o h \
              --long project:,helm-release-name:,namespace:,oauth2-client-id:,oauth2-client-secret:,pubsub-subscription:,pubsub-sa-jsonkey-gcs-url:,clean \
              -n 'install-spinnaker.sh' \
              -- "$@")
if [ $? != 0 ] ; then 
   echo "Terminating..." >&2 
   exit 2
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

_CD_PROJECT_ID=""
_HELM_RELEASE_NAME=""
_SPINNAKER_NS="spinnaker"
_OAUTH2_CLIENT_ID=""
_OAUTH2_CLIENT_SECRET=""
_OAUTH2_ENABLED=false
_CLEAN=false
_PUBSUB_ENABLED=false
_PUBSUB_SUBSCRIPTION_NAME=""

while true ; do
	case "$1" in
    --project) _CD_PROJECT_ID=$2; shift 2;;
    --helm-release-name) _HELM_RELEASE_NAME=$2; shift 2;;
    --namespace) _SPINNAKER_NS=$2; shift 2;;
    --oauth2-client-id) _OAUTH2_CLIENT_ID=$2; shift 2;;
    --oauth2-client-secret) _OAUTH2_CLIENT_SECRET=$2; shift 2;;
    --pubsub-subscription) _PUBSUB_SUBSCRIPTION_NAME=$2; shift 2;;
    --clean) _CLEAN=true; shift ;;
	  --) shift ; break ;;
	  *) echo "Internal error!" ; usage ;;
	esac
done

if [[ ! -z "$*" || -z "$_CD_PROJECT_ID" ]]; then
   usage
fi

[[ -z "$_HELM_RELEASE_NAME" ]] && _HELM_RELEASE_NAME="${_CD_PROJECT_ID}-spin"

if [[ ! -z "$_OAUTH2_CLIENT_ID" && ! -z "$_OAUTH2_CLIENT_SECRET" ]]; then
  _OAUTH2_ENABLED=true
fi

if [[ ! -z "$_PUBSUB_SUBSCRIPTION_NAME" ]]; then
  _PUBSUB_ENABLED=true
fi


echo
echo "---------------- Parameters ------------------"
echo "              Project Id: $_CD_PROJECT_ID"
echo "            Release Name: $_HELM_RELEASE_NAME"
echo "     Spinnaker Namespace: $_SPINNAKER_NS"
echo "          OAuth2 Enabled: $_OAUTH2_ENABLED"
echo "          Pubsub Enabled: $_PUBSUB_ENABLED"
echo "Pubsub Subscription Name: $_PUBSUB_SUBSCRIPTION_NAME"
echo "                   Clean: $_CLEAN"
echo

# Done processing command line arguments

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/install-spinnaker.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function cleanUpPreviousInstallation() {
  echo
  echo "Removing previous installation"
  helm --debug delete --purge  ${_HELM_RELEASE_NAME} --timeout 300 || true

  # now delete the CRB
  #kubectl delete clusterrolebinding -l release="${_HELM_RELEASE_NAME}" || true

  # now delete the release objects
  #kubectl --namespace ${_SPINNAKER_NS} delete all -l release="${_HELM_RELEASE_NAME}" || true

  # now delete the running jobs,pods
  #kubectl --namespace ${_SPINNAKER_NS} delete job,pod --all || true

  # now delete the tillerless storage
  #kubectl --namespace kube-system delete secret "${_HELM_RELEASE_NAME}.v1" || true

  # wait till spinnaker workloads are removed
  while [[ ! -z "$(kubectl --namespace ${_SPINNAKER_NS} get po -o=jsonpath='{.items[*].metadata.name}')" ]]; do
    sleep 3
  done

  echo "Previous installation removed"
  echo
}

function createAdditinoalConfigMap() {

  echo
  echo "Creating configmap for halyard additional config"

  local configmap_file=$(tempFile additional-config)
  cat <<EOF_KUBECTL > $configmap_file
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
      "${_CD_PROJECT_ID}" \
      "${_SPINNAKER_NS}" \
      "${_OAUTH2_ENABLED}" \
      "${_OAUTH2_CLIENT_ID}" \
      "${_OAUTH2_CLIENT_SECRET}" \
      "${_PUBSUB_ENABLED}" \
      "${_PUBSUB_SUBSCRIPTION_NAME}"
EOF_KUBECTL

  # Configure halyard-additional-config.sh, halyard-app-config.sh scripts as extra data in configmap so that they will
  # be mounted into helm install job pod
  kubectl create configmap test-$$ --from-file=halyard-additional-config.sh --dry-run -o yaml \
    | yq r - 'data'  \
    | sed "s/^/  /" >> $configmap_file

  kubectl create configmap test-$$ --from-file=halyard-app-config.sh --dry-run -o yaml \
    | yq r - 'data'  \
    | sed "s/^/  /" >> $configmap_file

  # validate the config file
  kubeval $configmap_file

  kubectl apply -f $configmap_file
}

function invokeHelm() {
  # Replace the placeholders in values.yaml
  echo
  echo "Helming now"
  set -x
  helm --debug upgrade --install ${_HELM_RELEASE_NAME} stable/spinnaker \
    --timeout 1200 \
    --wait \
    --namespace ${_SPINNAKER_NS} \
    --values values.yaml
}

# Main logic starts here

if [[ "${_CLEAN}" == "true" || ! -z "$(helm status ${_HELM_RELEASE_NAME} 2> /dev/null | grep 'STATUS: \(FAILED\|PENDING\)' )" ]]; then
  cleanUpPreviousInstallation
fi

createAdditinoalConfigMap

invokeHelm
