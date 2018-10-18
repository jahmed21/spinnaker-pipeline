#!/usr/bin/env bash

set -xeo pipefail

source /opt/halyard/additionalConfigMaps/common-functions.sh

$HAL_COMMAND config edit --timezone "Australia/Melbourne"