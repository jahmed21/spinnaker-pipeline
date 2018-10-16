#!/usr/bin/env bash

set -xeo pipefail

source /opt/halyard/additionalConfigMaps/common-functions.sh

_OAUTH2_CLIENT_ID=$(getSecretValue oauth-client-id)
_OAUTH2_CLIENT_SECRET=$(getSecretValue oauth-client-secret)
_GATE_BASE_URL=$(getConfigValue gate-base-url)
_GATE_URL_CONFIG_SCRIPT=/opt/halyard/additionalScripts/gate-url-config.sh

if [[ ! -f $_GATE_URL_CONFIG_SCRIPT ]]; then
  echo "Error. gate-base-url is mandatory to enable OAUTH"
  exit 1
fi

bash $_GATE_URL_CONFIG_SCRIPT

$HAL_COMMAND config security authn oauth2 edit \
                --client-id ${_OAUTH2_CLIENT_ID} \
                --client-secret ${_OAUTH2_CLIENT_SECRET} \
                --provider google \
                --pre-established-redirect-uri  "${_GATE_BASE_URL}/login"

$HAL_COMMAND config security authn oauth2 enable
