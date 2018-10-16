#!/usr/bin/env bash

set -eo pipefail

declare -A OPTS=(
                       ["project:"]="Project Id of the Spinnaker deployment project (Mandatory)"
             ["helm-release-name:"]="Helm release name"
                 ["chart-version:"]="Spinnaker chart version (default to 1.1.4)"
              ["oauth2-json-name:"]="Google OAUTH2 client secret json file"
                 ["gate-base-url:"]="Gate override base url"
                   ["ui-base-url:"]="UI override base url"
           ["pubsub-subscription:"]="Name of the pubsub subscription to be used by spinnaker"
["spinnaker-gcp-sa-key-json-name:"]="Spinnaker GCP SA key json file stored in project's halyard-config bucket (Mandatory)"
               ["enable-gate-x509"]="X509 Client Auth enabled for Gate (used by roer)"
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
_GATE_X509_ENABLED=false

VALUES_FILE=values-updated.yaml
SPINNAKER_NS="spinnaker"

while true ; do
	case "$1" in
    --project) _CD_PROJECT_ID=$2; shift 2;;
    --helm-release-name) _HELM_RELEASE_NAME=$2; shift 2;;
    --oauth2-json-name) _OAUTH2_JSON_NAME=$2; shift 2;;
    --gate-base-url) _GATE_BASE_URL=$2; shift 2;;
    --ui-base-url) _UI_BASE_URL=$2; shift 2;;
    --pubsub-subscription) _PUBSUB_SUBSCRIPTION_NAME=$2; shift 2;;
    --chart-version) _CHART_VERSION=$2; shift 2;;
    --spinnaker-gcp-sa-key-json-name) _SPINNAKER_GCP_SA_KEY_JSON_NAME=$2; shift 2;;
    --enable-gate-x509) _GATE_X509_ENABLED=true; shift ;;
	  --) shift ; break ;;
	  *) echo "Internal error!" ; usage ;;
	esac
done

[[ -z "$_HELM_RELEASE_NAME" ]] && _HELM_RELEASE_NAME="${_CD_PROJECT_ID}-spin"

echo
echo "---------------- Parameters ------------------"
echo "              Project Id: $_CD_PROJECT_ID"
echo "    GCP SA Key JSON Name: $_SPINNAKER_GCP_SA_KEY_JSON_NAME"
echo "            Release Name: $_HELM_RELEASE_NAME"
echo " Spinnaker Chart Version: $_CHART_VERSION"
echo "           Gate Base URL: $_GATE_BASE_URL"
echo "             UI Base URL: $_UI_BASE_URL"
echo "PubSub Subscription Name: $_PUBSUB_SUBSCRIPTION_NAME"
echo "        OAuth2 JSON Name: $_OAUTH2_JSON_NAME"
echo "       Gate X509 Enabled: $_GATE_X509_ENABLED"
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

function configureFileAsSecret() {
  local values_file=$1
  local filePath=$2
  local encodedValue="$(cat ${filePath} | base64 --wrap=0)"
  if [[ -z  "$encodedValue" ]]; then
    echo "File '$filePath' not found"
    exit 1
  fi
  addDataToValues $values_file "additionalSecrets"  $(basename $filePath) "${encodedValue}"
}

function configureValueAsSecret() {
  local values_file=$1
  local secretName=$2
  local secretValue=$3

  if [[ -z "${secretValue}" ]]; then
    echo "Error. empty secret value for '$secretName'"
    exit 1
  fi
  addDataToValues $values_file "additionalSecrets"  $secretName "$(echo "$secretValue" | base64 --wrap=0)"
}

function configureAdditionalConfigValue() {
  local values_file=$1
  local configName=$2
  local configValue=$3
  addDataToValues $values_file "additionalConfigMaps"  ${configName}  "${configValue}"
}

function configureAdditionalConfigFile() {
  local values_file=$1
  local file=$2
  configureAdditionalConfigValue $values_file "$(basename $file)" "$(cat $file)"
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
  set +x
}

function configureDockerRegistryPassword() {
  local values_file=$1
  yq w -i $values_file "dockerRegistries[0].password"  \
      "$(gsutil cat gs://${_CD_PROJECT_ID}-halyard-config/${_SPINNAKER_GCP_SA_KEY_JSON_NAME})"
}

function configureGCSStorage() {
  local values_file=$1
  yq w -i $values_file "gcs.jsonKey"  \
      "$(gsutil cat gs://${_CD_PROJECT_ID}-halyard-config/${_SPINNAKER_GCP_SA_KEY_JSON_NAME})"
  yq w -i $values_file "gcs.project" "${_CD_PROJECT_ID}"
  yq w -i $values_file "gcs.bucket"  "${_CD_PROJECT_ID}-spinnaker-config"
}

# Development only, this needs to be integrated with real CA. Will not be part of this script in the future
function generateDevelopmentX509Certificate() {
  local values_file=$1
  local jksstorepass=$2
  local keystore_file=$3

  local ca_key_password=$jksstorepass
  local gate_x509_ca_crt_file=gate-x509-ca.crt
  local gate_x509_ca_key_file=gate-x509-ca.key
  local ca_subject="/C=AU/ST=VIC/L=Melbourne/O=ANZ/OU=EX/CN=ca@spinnaker.ex.anz.com"

  local server_key_password=$jksstorepass
  local gate_x509_server_key_file=gate-x509-server.key
  local gate_x509_server_csr_file=gate-x509-server.csr
  local gate_x509_server_crt_file=gate-x509-server.crt
  local gate_x509_server_p12_file=gate-x509-server.p12
  local server_subject="/C=AU/ST=VIC/L=Melbourne/O=ANZ/OU=EX/CN=localhost"

  # roer does not support key with passphrase https://github.com/spinnaker/roer/issues/7
  local roer_key_file=roer.key
  local roer_csr_file=roer.csr
  local roer_crt_file=roer.crt
  local roer_subject="/C=AU/ST=VIC/L=Melbourne/O=ANZ/OU=EX/CN=roer@spinnaker.ex.anz.com"

  #
  # CA 
  #
  # Generate CA key
  openssl genrsa \
          -des3 \
          -passout pass:"$ca_key_password" \
          -out $gate_x509_ca_key_file \
          4096

  # Generate CA Certificate
  openssl req \
          -new \
          -x509 \
          -days 365 \
          -key $gate_x509_ca_key_file \
          -passin pass:"$ca_key_password" \
          -out $gate_x509_ca_crt_file \
          -subj "$ca_subject"

  #
  # Server 
  #
  # Generate server Key
  openssl genrsa \
          -des3 \
          -passout pass:"$server_key_password" \
          -out $gate_x509_server_key_file \
          4096

  # Generate a certificate signing request for the server
  openssl req \
          -new \
          -key $gate_x509_server_key_file \
          -passin pass:"$server_key_password" \
          -out $gate_x509_server_csr_file \
          -subj "$server_subject"

  # Use the CA to sign the server’s request
  openssl x509 \
          -req \
          -days 365 \
          -in $gate_x509_server_csr_file \
          -CA $gate_x509_ca_crt_file \
          -CAkey $gate_x509_ca_key_file \
          -passin pass:"$ca_key_password" \
          -CAcreateserial \
          -out $gate_x509_server_crt_file 

  #Format server certificate into Java Keystore (JKS) importable form.
  openssl pkcs12 \
          -export \
          -clcerts \
          -in $gate_x509_server_crt_file \
          -inkey $gate_x509_server_key_file \
          -passin pass:$server_key_password \
          -out $gate_x509_server_p12_file \
          -name spinnaker \
          -password pass:$jksstorepass

  #
  # Client 
  #
  # Generate Client Key
  openssl genrsa \
          -out $roer_key_file \
          4096

  # Generate a certificate signing request for the server
  openssl req \
          -new \
          -key $roer_key_file \
          -out $roer_csr_file \
          -subj "$roer_subject"

  # Use the CA to sign the server’s request
  openssl x509 \
          -req \
          -days 365 \
          -in $roer_csr_file \
          -CA $gate_x509_ca_crt_file \
          -CAkey $gate_x509_ca_key_file \
          -passin pass:"$ca_key_password" \
          -CAcreateserial \
          -out $roer_crt_file 

  #
  # Keystore 
  #
  # Create Java Keystore by importing CA certificate
  keytool -import \
          -trustcacerts \
          -file $gate_x509_ca_crt_file \
          -keystore $keystore_file \
          -noprompt \
          -storepass $jksstorepass \
          -alias ca

  # Import server's certificate
  keytool -importkeystore \
          -noprompt \
          -srckeystore $gate_x509_server_p12_file \
          -srcstoretype pkcs12 \
          -srcalias spinnaker \
          -srcstorepass $jksstorepass \
          -destkeystore $keystore_file \
          -deststoretype jks \
          -destalias spinnaker \
          -deststorepass $jksstorepass \
          -destkeypass $jksstorepass

  #Import the client certificate into the keystore
  keytool -import \
          -noprompt \
          -file $roer_crt_file \
          -keystore $keystore_file \
          -storepass $jksstorepass  \
          -alias client

  configureFileAsSecret  $values_file "$gate_x509_ca_crt_file"
  configureFileAsSecret  $values_file "$gate_x509_ca_key_file"
  configureFileAsSecret  $values_file "$gate_x509_server_crt_file"
  configureFileAsSecret  $values_file "$gate_x509_server_key_file"
  configureFileAsSecret  $values_file "$roer_crt_file"
  configureFileAsSecret  $values_file "$roer_key_file"
  configureValueAsSecret $values_file "${gate_x509_ca_key_file}.password"  $ca_key_password
  configureValueAsSecret $values_file "${gate_x509_server_key_file}.password"  $server_key_password
}

function configureGateX509Cert() {
  local values_file=$1
  local jksstorepass="changedit"
  local keystore_file="gate-x509.jks"

  # Development only, this needs to be integrated with real CA. Will not be part of this script in the future
  generateDevelopmentX509Certificate  $values_file $jksstorepass $keystore_file

  # Store the JKS and it's password into additional secret, will be used by gate-x509-config.sh
  configureFileAsSecret  $values_file $keystore_file
  configureValueAsSecret $values_file "${keystore_file}.password" $jksstorepass

  # Register gate-x509-config.sh as additional script to be run during helm install
  configureAdditionalScripts  $VALUES_FILE  gate-x509-config.sh

  # Change the X509 parameters in the file 
  local gate_local_file=gate-local.yml
  yq w -i $gate_local_file "server.ssl.keyStorePassword" $jksstorepass
  yq w -i $gate_local_file "server.ssl.trustStorePassword" $jksstorepass

  configureFileAsSecret $VALUES_FILE $gate_local_file
}

function patch() {
  local type=$1
  local name=$2
  local patch_file=$3
  local json_path=$4
  local match_str=$5

  echo "About to patch $name $type"
  declare -i cntr=30
  while ((cntr--)); do
    local out=$(kubectl -n ${SPINNAKER_NS} get $type $name  -o=jsonpath=$json_path)
    if [[ ! -z "$out" ]]; then
      echo "JSON Path '$json_path' output is '$out'"
      if echo "$out" | grep -q  "$match_str"; then
        echo "$name $type already patched"
      else
        echo "Patching $name $type"
        kubectl -n ${SPINNAKER_NS} patch $type $name --patch "$(cat $patch_file)"
      fi
      break;
    fi
    echo "Waiting for $name $type to be ready....$cntr"
    sleep 10
  done

  if [[ $cntr -lt 0 ]]; then
    echo "Failed to patch $name $type. Timedout...."
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

# Configure additionalScripts
configureAdditionalScripts  $VALUES_FILE  debug-config.sh

# Configure halyard-app-config.sh as additionalConfigMaps
configureAdditionalConfigFile  $VALUES_FILE  halyard-app-config.sh

# Configure common-functions.sh as additionalConfigMaps, used by other config scripts
configureAdditionalConfigFile  $VALUES_FILE  common-functions.sh

# Update docker registry password in values file
configureDockerRegistryPassword $VALUES_FILE

# Update GCS storage credential in values file
configureGCSStorage $VALUES_FILE

# Below values are configured as additionalConfigMap items, so that scripts can get these values
configureAdditionalConfigValue  $VALUES_FILE  "project-id"  "${_CD_PROJECT_ID}"

# Create OAuth Client Id & Secret as additionalSecrets
if [[ ! -z "${_OAUTH2_JSON_NAME}" ]]; then
  configureAdditionalScripts  $VALUES_FILE  oauth-config.sh
  configureValueAsSecret $VALUES_FILE  "oauth-client-id"  \
            "$(gsutil cat gs://${_CD_PROJECT_ID}-halyard-config/${_OAUTH2_JSON_NAME} | jq -Mr .web.client_id)"
  configureValueAsSecret $VALUES_FILE  "oauth-client-secret"  \
            "$(gsutil cat gs://${_CD_PROJECT_ID}-halyard-config/${_OAUTH2_JSON_NAME} | jq -Mr .web.client_secret)"
fi

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

if [[ $_GATE_X509_ENABLED ]]; then
  configureGateX509Cert $VALUES_FILE
fi

invokeHelm

if [[ $_GATE_X509_ENABLED ]]; then
  patchGateDeployment
fi
