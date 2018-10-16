#!/usr/bin/env bash

set -xeo pipefail

source /opt/halyard/additionalConfigMaps/common-functions.sh

$HAL_COMMAND config security api edit --override-base-url $(getConfigValue gate-base-url)