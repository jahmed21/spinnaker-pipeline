#!/usr/bin/env bash

set -xeo pipefail

source /opt/halyard/additionalConfigMaps/common-functions.sh

_OAUTH2_CLIENT_ID=$(getSecretValue oauth-client-id)
_OAUTH2_CLIENT_SECRET=$(getSecretValue oauth-client-secret)
_GATE_BASE_URL=$(getConfigValue gate-base-url)
_OAUTH2_REDIRECT_URL=$(getConfigValue oauth-redirect-url)


$HAL_COMMAND config security authn oauth2 edit \
                --client-id ${_OAUTH2_CLIENT_ID} \
                --client-secret ${_OAUTH2_CLIENT_SECRET} \
                --provider google \
                --pre-established-redirect-uri  "${_OAUTH2_REDIRECT_URL}"

$HAL_COMMAND config security authn oauth2 enable
