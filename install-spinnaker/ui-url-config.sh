#!/usr/bin/env bash

set -xeo pipefail

source /opt/halyard/additionalConfigMaps/common-functions.sh

$HAL_COMMAND config security ui edit --override-base-url $(getConfigValue ui-base-url)