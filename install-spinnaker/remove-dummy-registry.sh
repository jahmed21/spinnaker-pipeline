#!/usr/bin/env bash

set -xeo pipefail

# Delete the dummmy docker-registry created as part of helm install (mandatory in spinnaker chart)
if $HAL_COMMAND config provider docker-registry account get dummy 2>/dev/null; then
  $HAL_COMMAND config provider docker-registry account delete dummy
fi
