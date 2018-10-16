#!/usr/bin/env bash

set -xeo pipefail

source /opt/halyard/additionalConfigMaps/common-functions.sh

_KEYSTORE_PATH=$(getSecretFilePath gate-x509.jks)
_GATE_URL_CONFIG_SCRIPT=/opt/halyard/additionalScripts/gate-url-config.sh

if [[ ! -f $_GATE_URL_CONFIG_SCRIPT ]]; then
  echo "Error. gate-base-url and ui-base-url are mandatory to enable gate x509"
  exit 1
fi

bash $_GATE_URL_CONFIG_SCRIPT

$HAL_COMMAND config security api ssl edit \
    --key-alias spinnaker \
    --keystore $_KEYSTORE_PATH \
    --keystore-type jks \
    --truststore $_KEYSTORE_PATH \
    --truststore-type jks

$HAL_COMMAND config security api ssl enable 

$HAL_COMMAND config security authn x509 enable

kubectl exec $HALYARD_POD -- bash -c "
  set -xeo pipefail;
  mkdir -p ~/.hal/default/profiles;
  cat ${ADDITIONAL_SECRETS_DIR}/gate-local.yml > ~/.hal/default/profiles/gate-local.yml;
  echo 'port: 9001' > ~/.hal/default/service-settings/gate.yml;
  "