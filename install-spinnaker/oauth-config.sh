#!/usr/bin/env bash

set -xeo pipefail

ADDITIONAL_CONFIGMAP_DIR="/opt/halyard/additionalConfigMaps"
ADDITIONAL_SECRETS_DIR="/opt/halyard/additionalSecrets"

getAdditionalConfigValue() {
  local dir=$1
  local fileName=$2
  local filePath="${dir}/${fileName}"
  if [[ -f "$filePath" && -r "$filePath" ]]; then
    cat "$filePath"
  fi
}

_OAUTH2_CLIENT_ID="$(getAdditionalConfigValue $ADDITIONAL_SECRETS_DIR oauth-client-id)"
_OAUTH2_CLIENT_SECRET="$(getAdditionalConfigValue $ADDITIONAL_SECRETS_DIR oauth-client-secret)"

# Config google oauth
$HAL_COMMAND config security api edit --override-base-url $(getAdditionalConfigValue $ADDITIONAL_SECRETS_DIR gate-base-url)

$HAL_COMMAND config security authn oauth2 edit \
                --client-id ${_OAUTH2_CLIENT_ID} \
                --client-secret ${_OAUTH2_CLIENT_SECRET} \
                --provider google \
                --pre-established-redirect-uri  "$(getAdditionalConfigValue $ADDITIONAL_SECRETS_DIR gate-base-url)/login"

$HAL_COMMAND config security authn oauth2 enable
