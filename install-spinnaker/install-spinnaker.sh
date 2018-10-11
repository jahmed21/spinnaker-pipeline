#!/usr/bin/env bash

set -eo pipefail

declare -A OPTS=(
                      ["project:"]="Project Id of the Spinnaker deployment project"
            ["helm-release-name:"]="Helm release name"
                ["chart-version:"]="Spinnaker chart version (default to 1.1.4)"
             ["oauth2-json-name:"]="Google OAUTH2 client secret json file"
                ["gate-base-url:"]="Gate override base url"
          ["pubsub-subscription:"]="Name of the pubsub subscription to be used by spinnaker"
      ["pubsub-sa-key-json-name:"]="Name of the pubusb key json file stored in project's halyard-config bucket"
         ["gcs-sa-key-json-name:"]="Name of the gcs key json file stored in project's halyard-config bucket"
                         ["clean"]="Uninstall previous helm installation first"
      )

function usage() {
  echo
  echo "usage $(basename $0)"
  for opt in "${!OPTS[@]}"; do
    local pname=$(echo "$opt" | tr -d ':')
    printf "  %-30s %s\n" "--${pname}" "${OPTS[$opt]}"
  done
  exit 1
}

LONG_OPTS=$(echo "${!OPTS[@]}" | tr ' ' ',')

# Process command line arguments
TEMP=$(getopt -o h \
              --long $LONG_OPTS \
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
_OAUTH2_JSON_NAME=""
_CLEAN=false
_PUBSUB_SUBSCRIPTION_NAME=""
_CHART_VERSION="1.1.4"
_GCS_SA_KEY_JSON_NAME=""
_PUBSUB_SA_KEY_JSON_NAME=""
_GATE_BASE_URL=""

VALUES_FILE=values-updated.yaml
SPINNAKER_NS="spinnaker"

while true ; do
	case "$1" in
    --project) _CD_PROJECT_ID=$2; shift 2;;
    --helm-release-name) _HELM_RELEASE_NAME=$2; shift 2;;
    --oauth2-json-name) _OAUTH2_JSON_NAME=$2; shift 2;;
    --gate-base-url) _GATE_BASE_URL=$2; shift 2;;
    --pubsub-subscription) _PUBSUB_SUBSCRIPTION_NAME=$2; shift 2;;
    --chart-version) _CHART_VERSION=$2; shift 2;;
    --pubsub-sa-key-json-name) _PUBSUB_SA_KEY_JSON_NAME=$2; shift 2;;
    --gcs-sa-key-json-name) _GCS_SA_KEY_JSON_NAME=$2; shift 2;;
    --clean) _CLEAN=true; shift ;;
	  --) shift ; break ;;
	  *) echo "Internal error!" ; usage ;;
	esac
done

if [[ ! -z "$*" || -z "$_CD_PROJECT_ID" || -z "${_GCS_SA_KEY_JSON_NAME}" ]]; then
   usage
fi

[[ -z "$_HELM_RELEASE_NAME" ]] && _HELM_RELEASE_NAME="${_CD_PROJECT_ID}-spin"

echo
echo "---------------- Parameters ------------------"
echo "              Project Id: $_CD_PROJECT_ID"
echo "            Release Name: $_HELM_RELEASE_NAME"
echo " Spinnaker Chart Version: $_CHART_VERSION"
echo "        OAuth2 JSON Name: $_OAUTH2_JSON_NAME"
echo "           Gate Base URL: $_GATE_BASE_URL"
echo "PubSub Subscription Name: $_PUBSUB_SUBSCRIPTION_NAME"
echo " PubSub SA Key JSON Name: $_PUBSUB_SA_KEY_JSON_NAME"
echo "    GCS SA Key JSON Name: $_GCS_SA_KEY_JSON_NAME"
echo "                   Clean: $_CLEAN"
echo

# Done processing command line arguments

function addDataToValues() {
  local values_file=$1
  local key=$2
  local dataName=$3
  local dataValue="$4"

  if [[ -z "${dataValue}" ]]; then
    echo "Error. empty value for config '$key'-'$dataName'"
    exit 1
  fi
  echo "Configuring '$key'-'$dataName'"
  yq w -i $values_file "halyard.${key}.data.[${dataName}]"  "$dataValue"
}

function configureAdditionalScripts() {
  local values_file=$1
  local file=$2
  addDataToValues $values_file "additionalScripts"  $(basename $file) "$(cat $file)"
}

function configureHalyardConfigSecret() {
  local values_file=$1
  local secretName=$2
  local keyJSONFileName=$3
  local encodedValue="$(gsutil cat gs://${_CD_PROJECT_ID}-halyard-config/${keyJSONFileName} | base64 --wrap=0)"
  if [[ -z  "$encodedValue" ]]; then
    echo "Halyard Config '$keyJSONFileName' not found at gs://${_CD_PROJECT_ID}-halyard-config/${keyJSONFileName}"
    exit 1
  fi
  addDataToValues $values_file "additionalSecrets"  $secretName "${encodedValue}"
}

function configOAuthSecrets() {
  local values_file=$1
  local secretName=$2
  local secretValue=$3

  if [[ -z "${secretValue}" ]]; then
    echo "Error. empty secret value for '$secretName'"
    exit 1
  fi
  addDataToValues $values_file "additionalSecrets"  $secretName "$(echo "$secretValue" | base64 --wrap=0)"
}

function configureAdditionalConfigs() {
  local values_file=$1
  local configName=$2
  local configValue=$3
  addDataToValues $values_file "additionalConfigMaps"  ${configName}  "${configValue}"
}

function configureAdditionalConfigFile() {
  local values_file=$1
  local file=$2
  configureAdditionalConfigs $values_file "$(basename $file)" "$(cat $file)"
}

function invokeHelm() {
  # Replace the placeholders in values.yaml
  echo
  echo "Helming now"
  set -x
  helm upgrade ${_HELM_RELEASE_NAME} stable/spinnaker \
    --install \
    --debug \
    --timeout 900 \
    --namespace ${SPINNAKER_NS} \
    --version  ${_CHART_VERSION} \
    --values ${VALUES_FILE}
}

# Main logic starts here

cp values.yaml $VALUES_FILE

# Configure additionalScripts
configureAdditionalScripts  $VALUES_FILE  gcs-config.sh
configureAdditionalScripts  $VALUES_FILE  debug-config.sh
configureAdditionalScripts  $VALUES_FILE  remove-dummy-registry.sh

# Configure halyard-app-config.sh as additionalConfigMaps
configureAdditionalConfigFile  $VALUES_FILE  halyard-app-config.sh

# Configure spinnaker-local.yml as additionalConfigMaps
configureAdditionalConfigFile  $VALUES_FILE  spinnaker-local.yml

# Copy gcs key from halyard-config bucket into additionSecrets
configureHalyardConfigSecret $VALUES_FILE  "gcs.json"  $_GCS_SA_KEY_JSON_NAME

# Copy pubsub key from halyard-config bucket into additionSecrets
if [[ ! -z "$_PUBSUB_SA_KEY_JSON_NAME" ]]; then
  configureHalyardConfigSecret $VALUES_FILE  "pubsub.json"  $_PUBSUB_SA_KEY_JSON_NAME
fi

# Create OAuth Client Id & Secret as additionalSecrets

if [[ ! -z "${_OAUTH2_JSON_NAME}" ]]; then
  configureAdditionalScripts  $VALUES_FILE  oauth-config.sh
  configOAuthSecrets $VALUES_FILE  "oauth-client-id"  \
            "$(gsutil cat gs://${_CD_PROJECT_ID}-halyard-config/${_OAUTH2_JSON_NAME} | jq -Mr .web.client_id)"
  configOAuthSecrets $VALUES_FILE  "oauth-client-secret"  \
            "$(gsutil cat gs://${_CD_PROJECT_ID}-halyard-config/${_OAUTH2_JSON_NAME} | jq -Mr .web.client_secret)"
  configOAuthSecrets $VALUES_FILE  "gate-base-url"  "${_GATE_BASE_URL}"
fi


# Below values are configured as additionalConfigMap items, so that scripts can get these values
configureAdditionalConfigs  $VALUES_FILE  "project-id"  "${_CD_PROJECT_ID}"

if [[ ! -z "$_PUBSUB_SUBSCRIPTION_NAME" ]]; then
  configureAdditionalScripts  $VALUES_FILE  pubsub-config.sh
  configureAdditionalConfigs  $VALUES_FILE  "pubsub-subscription-name"  "${_PUBSUB_SUBSCRIPTION_NAME}"
fi

invokeHelm
