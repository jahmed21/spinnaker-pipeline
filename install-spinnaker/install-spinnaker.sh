#!/usr/bin/env bash

set -eo pipefail

declare -A OPTS=(
                       ["project:"]="Project Id of the Spinnaker deployment project (Mandatory)"
             ["helm-release-name:"]="Helm release name"
                 ["chart-version:"]="Spinnaker chart version (default to 1.1.4)"
           ["pubsub-subscription:"]="Name of the pubsub subscription to be used by spinnaker"
["spinnaker-gcp-sa-key-json-name:"]="Spinnaker GCP SA key json file stored in project's halyard-config bucket (Mandatory)"
              ["oauth2-json-name:"]="Google OAUTH2 client secret json file"
           ["oauth2-redirect-url:"]="OAUTH2 Redirect URL"
                   ["ui-base-url:"]="UI override base url"
                 ["gate-base-url:"]="Gate override base url"
              ["gate-x509-ca-crt:"]="CA Certificate for Gate's X509 Authentication"
          ["gate-x509-server-crt:"]="Server Certificate for Gate's X509 Authentication"
          ["gate-x509-server-key:"]="Server Private Key for Gate's X509 Authentication"
     ["gate-x509-server-key-pass:"]="Server Private Key's Password"
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
TEMP=$(getopt -o h --long $LONG_OPTS -n 'install-spinnaker.sh' -- "$@")
if [ $? != 0 ] ; then 
   echo "Terminating..." >&2 
   exit 2
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

_CD_PROJECT_ID=""
_HELM_RELEASE_NAME=""
_OAUTH2_JSON_NAME=""
_PUBSUB_SUBSCRIPTION_NAME=""
_CHART_VERSION="1.1.4"
_SPINNAKER_GCP_SA_KEY_JSON_NAME=""
_GATE_BASE_URL=""
_UI_BASE_URL=""
_OAUTH2_REDIRECT_URL=""
_GATE_X509_ENABLED=false
_GATE_X509_CA_CRT=""
_GATE_X509_SERVER_CRT=""
_GATE_X509_SERVER_KEY=""
_GATE_X509_SERVER_KEY_PASS=""

VALUES_FILE=values-updated.yaml
SPINNAKER_NS="spinnaker"

while true ; do
	case "$1" in
    --project) _CD_PROJECT_ID=$2; shift 2;;
    --helm-release-name) _HELM_RELEASE_NAME=$2; shift 2;;
    --chart-version) _CHART_VERSION=$2; shift 2;;
    --spinnaker-gcp-sa-key-json-name) _SPINNAKER_GCP_SA_KEY_JSON_NAME=$2; shift 2;;
    --pubsub-subscription) _PUBSUB_SUBSCRIPTION_NAME=$2; shift 2;;
    --oauth2-json-name) _OAUTH2_JSON_NAME=$2; shift 2;;
    --oauth2-redirect-url) _OAUTH2_REDIRECT_URL=$2; shift 2;;
    --ui-base-url) _UI_BASE_URL=$2; shift 2;;
    --gate-base-url) _GATE_BASE_URL=$2; shift 2;;
    --gate-x509-ca-crt) _GATE_X509_CA_CRT=$2; shift 2;;
    --gate-x509-server-crt) _GATE_X509_SERVER_CRT=$2; shift 2;;
    --gate-x509-server-key) _GATE_X509_SERVER_KEY=$2; shift 2;;
    --gate-x509-server-key-pass) _GATE_X509_SERVER_KEY_PASS=$2; shift 2;;
	  --) shift ; break ;;
	  *) echo "Internal error!" ; usage ;;
	esac
done

[[ -z "$_HELM_RELEASE_NAME" ]] && _HELM_RELEASE_NAME="${_CD_PROJECT_ID}-spin"

[[ ! -z "$_GATE_X509_SERVER_KEY_PASS" && \
   ! -z "$_GATE_X509_SERVER_KEY" && \
   ! -z "$_GATE_X509_SERVER_CRT" && \
   ! -z "$_GATE_X509_CA_CRT" ]] && _GATE_X509_ENABLED=true

echo
echo "---------------- Parameters ------------------"
echo "              Project Id: $_CD_PROJECT_ID"
echo "    GCP SA Key JSON Name: $_SPINNAKER_GCP_SA_KEY_JSON_NAME"
echo "            Release Name: $_HELM_RELEASE_NAME"
echo " Spinnaker Chart Version: $_CHART_VERSION"
echo "PubSub Subscription Name: $_PUBSUB_SUBSCRIPTION_NAME"
echo "             UI Base URL: $_UI_BASE_URL"
echo "     OAuth2 Redirect URL: $_OAUTH2_REDIRECT_URL"
echo "        OAuth2 JSON Name: $_OAUTH2_JSON_NAME"
echo "           Gate Base URL: $_GATE_BASE_URL"
echo "       Gate X509 Enabled: $_GATE_X509_ENABLED"
echo "           CA Certficate: $_GATE_X509_CA_CRT"
echo "       Server Certficate: $_GATE_X509_SERVER_CRT"
echo "              Server Key: $_GATE_X509_SERVER_KEY"
echo

if [[ ! -z "$*" || -z "$_CD_PROJECT_ID" || -z "${_SPINNAKER_GCP_SA_KEY_JSON_NAME}" ]]; then
   echo "Error. Invalid project id '$_CD_PROJECT_ID' or gcs json name '$_SPINNAKER_GCP_SA_KEY_JSON_NAME'"
   usage
fi

if [[ ! -z "$_OAUTH2_JSON_NAME" || $_GATE_X509_ENABLED ]] && [[ -z "$_GATE_BASE_URL" || -z "$_UI_BASE_URL" ]]; then
   echo "Error. Gate and UI base url are mandatory when OAUTH and/or X509 is enabled"
   usage
fi

# Done processing command line arguments

# Create a temp directory for all files generated during this execution
MYTMPDIR=$(mktemp -d /tmp/install-spinnaker.XXXX)
trap "rm -vrf $MYTMPDIR" EXIT

function tempFile() {
  mktemp ${MYTMPDIR}/${1}.XXXXX
}

function log() {
  >&2 echo
  >&2 echo "$(date): $@"
}


function gcsCat() {
  local path="gs://${_CD_PROJECT_ID}-halyard-config/$1"
  log "Getting content of file at $path"
  gsutil cat $path
}

function getLocalFile() {
  local path="gs://${_CD_PROJECT_ID}-halyard-config/$1"
  local filename=$(basename $1)
  local localpath=$(tempFile $filename)
  log "Getting local copy for $path -> $localpath"
  gsutil -q cp $path $localpath
  echo $localpath
}

function addDataToValuesYAML() {
  local values_file=$1
  local key=$2
  local dataName=$3
  local dataValue="$4"

  if [[ -z "${dataValue}" ]]; then
    log "Error. empty value for config $key $dataName"
    exit 1
  fi
  log "Configuring $key $dataName"
  yq w -i $values_file "halyard.${key}.data.[${dataName}]"  "$dataValue"
}

declare -i SCRIPT_INDEX=1
function configureAdditionalScripts() {
  local values_file=$1
  local file=$2
  local filename=$(basename $file)
  local index=$((SCRIPT_INDEX++))
  local keyName=$(printf "%02d-%s" $index $filename)
  addDataToValuesYAML $values_file "additionalScripts"  "$keyName" "$(cat $file)"
}


function configureHalyardConfigSecret() {
  local values_file=$1
  local secretName=$2
  local keyJSONFileName=$3
  local encodedValue="$(gcsCat $keyJSONFileName | base64 --wrap=0)"
  if [[ -z  "$encodedValue" ]]; then
    log "ERROR. Halyard Config '$keyJSONFileName' not found"
    exit 1
  fi
  addDataToValuesYAML $values_file "additionalSecrets"  $secretName "${encodedValue}"
}

function configureFileAsSecret() {
  local values_file=$1
  local filePath=$2
  local keyName=$3

  local encodedValue="$(cat ${filePath} | base64 --wrap=0)"
  if [[ -z  "$encodedValue" ]]; then
    log "File '$filePath' not found"
    exit 1
  fi

  if [[ -z "$keyName" ]]; then
    keyName="$(basename $filePath)"
  fi

  addDataToValuesYAML $values_file "additionalSecrets"  "$keyName" "${encodedValue}"
}

function configureValueAsSecret() {
  local values_file=$1
  local secretName=$2
  local secretValue=$3

  if [[ -z "${secretValue}" ]]; then
    log "Error. empty secret value for '$secretName'"
    exit 1
  fi
  addDataToValuesYAML $values_file "additionalSecrets"  $secretName "$(echo "$secretValue" | base64 --wrap=0)"
}

function configureAdditionalConfigValue() {
  local values_file=$1
  local configName=$2
  local configValue=$3
  addDataToValuesYAML $values_file "additionalConfigMaps"  ${configName}  "${configValue}"
}

function configureAdditionalConfigFile() {
  local values_file=$1
  local file=$2
  configureAdditionalConfigValue $values_file "$(basename $file)" "$(cat $file)"
}

function invokeHelm() {
  # Replace the placeholders in values.yaml
  log "Helming now"
  set -x
  helm upgrade ${_HELM_RELEASE_NAME} stable/spinnaker \
    --force \
    --install \
    --debug \
    --timeout 900 \
    --namespace ${SPINNAKER_NS} \
    --version  ${_CHART_VERSION} \
    --values ${VALUES_FILE}
  set +x
  log "Finished Helming"
}

function configureDockerRegistryPassword() {
  local values_file=$1
  yq w -i $values_file "dockerRegistries[0].password"  \
      "$(gcsCat $_SPINNAKER_GCP_SA_KEY_JSON_NAME)"
}

function configureGCSStorage() {
  local values_file=$1
  yq w -i $values_file "gcs.jsonKey"  \
      "$(gcsCat $_SPINNAKER_GCP_SA_KEY_JSON_NAME)"
  yq w -i $values_file "gcs.project" "${_CD_PROJECT_ID}"
  yq w -i $values_file "gcs.bucket"  "${_CD_PROJECT_ID}-spinnaker-config"
}

function prepareKeyStoreFileForServer() {
  local keystore_file=$1
  local gate_x509_ca_crt_file=$(getLocalFile $2)
  local gate_x509_server_crt_file=$(getLocalFile $3)
  local gate_x509_server_key_file=$(getLocalFile $4)
  local gate_x509_server_key_pass=$5

  local gate_x509_server_p12_file=$(tempFile server.p12)
  #
  # Format server certificate into Java Keystore (JKS) importable form.
  #
  openssl pkcs12 \
          -export \
          -clcerts \
          -in $gate_x509_server_crt_file \
          -inkey $gate_x509_server_key_file \
          -passin pass:$gate_x509_server_key_pass \
          -out $gate_x509_server_p12_file \
          -name spinnaker \
          -password pass:$gate_x509_server_key_pass

  #
  # Create Java Keystore by importing CA certificate
  keytool -import \
          -trustcacerts \
          -file $gate_x509_ca_crt_file \
          -keystore $keystore_file \
          -noprompt \
          -storepass $gate_x509_server_key_pass \
          -alias ca

  # Import server's certificate
  keytool -importkeystore \
          -noprompt \
          -srckeystore $gate_x509_server_p12_file \
          -srcstoretype pkcs12 \
          -srcalias spinnaker \
          -srcstorepass $gate_x509_server_key_pass \
          -destkeystore $keystore_file \
          -deststoretype jks \
          -destalias spinnaker \
          -deststorepass $gate_x509_server_key_pass \
          -destkeypass $gate_x509_server_key_pass
}

function configureGateX509Cert() {
  local values_file=$1
  local gate_x509_ca_crt_file=$2
  local gate_x509_server_crt_file=$3
  local gate_x509_server_key_file=$4
  local gate_x509_server_key_pass=$5

  local keystore_file=$(tempFile gate-x509.jks)
  local gate_local_file=$(tempFile gate-local.yml)

  # Remove the empty file created by tempFile command
  rm -f $keystore_file

  prepareKeyStoreFileForServer  \
        $keystore_file \
        $gate_x509_ca_crt_file \
        $gate_x509_server_crt_file \
        $gate_x509_server_key_file \
        $gate_x509_server_key_pass

  # Change the X509 parameters in the file
  cp gate-local.yml $gate_local_file
  yq w -i $gate_local_file "server.ssl.keyStorePassword" $gate_x509_server_key_pass
  yq w -i $gate_local_file "server.ssl.trustStorePassword" $gate_x509_server_key_pass

  configureFileAsSecret $values_file $gate_local_file "gate-local.yml"
  configureFileAsSecret $values_file $keystore_file "gate-x509.jks"

  # Register gate-x509-config.sh as additional script to be run during helm install
  configureAdditionalScripts  $values_file  gate-x509-config.sh
}

function patch() {
  local type=$1
  local name=$2
  local patch_file=$3
  local json_path=$4
  local match_str=$5

  log "About to patch $name $type"
  declare -i cntr=30
  while ((cntr--)); do
    local out=$(kubectl -n ${SPINNAKER_NS} get $type $name  -o=jsonpath=$json_path)
    if [[ ! -z "$out" ]]; then
      log "JSON Path '$json_path' output is '$out'"
      if echo "$out" | grep -q  "$match_str"; then
        log "$name $type already patched"
      else
        log "Patching $name $type"
        kubectl -n ${SPINNAKER_NS} patch $type $name --patch "$(cat $patch_file)"
      fi
      break;
    fi
    log "Waiting for $name $type to be ready....$cntr"
    sleep 10
  done

  if [[ $cntr -lt 0 ]]; then
    log "Failed to patch $name $type. Timedout...."
    exit 1
  fi
}

function patchGateDeployment() {
    patch  deployment spin-gate deployment-spin-gate-patch.yml '{.spec.template.spec.containers[].ports[*].containerPort}' 8085
    patch  service spin-gate service-spin-gate-patch.yml '{.spec.ports[*].port}' 8085
}


# Main logic starts here

cp values.yaml $VALUES_FILE

# Copy gcs key from halyard-config bucket into additionSecrets
configureHalyardConfigSecret $VALUES_FILE  "spinnaker-gcp-sa-access-key.json"  $_SPINNAKER_GCP_SA_KEY_JSON_NAME

# Configure spinnaker-local.yml as additionalConfigMaps
configureAdditionalConfigFile  $VALUES_FILE  spinnaker-local.yml

# Configure timezone
configureAdditionalScripts  $VALUES_FILE  timezone.sh

# Configure debug
configureAdditionalScripts  $VALUES_FILE  debug-config.sh

# Configure k8s-account-config.sh as additionalConfig, this script will be invoked by register-app-job
configureAdditionalConfigFile  $VALUES_FILE  k8s-account-config.sh

# Configure common-functions.sh as additionalConfigMaps, used by other config scripts
configureAdditionalConfigFile  $VALUES_FILE  common-functions.sh

# Update docker registry password in values file
configureDockerRegistryPassword $VALUES_FILE

# Update GCS storage credential in values file
configureGCSStorage $VALUES_FILE

# Below values are configured as additionalConfigMap items, so that scripts can get these values
configureAdditionalConfigValue  $VALUES_FILE  "project-id"  "${_CD_PROJECT_ID}"

if [[ ! -z "$_PUBSUB_SUBSCRIPTION_NAME" ]]; then
  configureAdditionalScripts  $VALUES_FILE  pubsub-config.sh
  configureAdditionalConfigValue  $VALUES_FILE  "pubsub-subscription-name"  "${_PUBSUB_SUBSCRIPTION_NAME}"
fi

if [[ ! -z "$_GATE_BASE_URL" ]]; then
  configureAdditionalScripts  $VALUES_FILE  gate-url-config.sh
  configureAdditionalConfigValue  $VALUES_FILE  "gate-base-url"  "${_GATE_BASE_URL}"
fi

if [[ ! -z "$_UI_BASE_URL" ]]; then
  configureAdditionalScripts  $VALUES_FILE  ui-url-config.sh
  configureAdditionalConfigValue  $VALUES_FILE  "ui-base-url"  "${_UI_BASE_URL}"
fi

# Create OAuth Client Id & Secret as additionalSecrets
if [[ ! -z "${_OAUTH2_JSON_NAME}" ]]; then
  if [[ ! -z "${_OAUTH2_REDIRECT_URL}" ]]; then
    configureAdditionalConfigValue  $VALUES_FILE  "oauth-redirect-url"  "${_OAUTH2_REDIRECT_URL}"
  fi
  configureAdditionalScripts  $VALUES_FILE  oauth-config.sh
  configureValueAsSecret $VALUES_FILE  "oauth-client-id"  \
            "$(gcsCat ${_OAUTH2_JSON_NAME} | jq -Mr .web.client_id)"
  configureValueAsSecret $VALUES_FILE  "oauth-client-secret"  \
            "$(gcsCat ${_OAUTH2_JSON_NAME} | jq -Mr .web.client_secret)"
fi

if [[ $_GATE_X509_ENABLED ]]; then
  configureGateX509Cert $VALUES_FILE \
      $_GATE_X509_CA_CRT \
      $_GATE_X509_SERVER_CRT \
      $_GATE_X509_SERVER_KEY \
      $_GATE_X509_SERVER_KEY_PASS
fi

invokeHelm

if [[ $_GATE_X509_ENABLED ]]; then
  patchGateDeployment
fi
