#!/usr/bin/env bash

set -xeo pipefail
cat <<EOF_KUBECTL | 
apiVersion: v1
kind: Namespace
metadata:
  name: ${SPINNAKER_NS}
spec:
  finalizers:
  - kubernetes
---
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    app: ${HELM_RELEASE_NAME}-spinnaker
    release: ${HELM_RELEASE_NAME}
  name: my-halyard-config
  namespace: ${SPINNAKER_NS}
data:
  config.sh: |
    set -xeo pipefail

    echo "\$HOME"

    HALYARD_POD=\$(kubectl -n ${SPINNAKER_NS}  get po \
                -l component=halyard,statefulset.kubernetes.io/pod-name \
                --field-selector status.phase=Running \
                -o jsonpath="{.items[0].metadata.name}")

    kubectl -n ${SPINNAKER_NS} exec \$HALYARD_POD -- bash -c "
    set -xeo pipefail;
    env | sort;
    find ~ -print;
    cat << EOF_CONFIG > ~/.hal/default/service-settings/gate.yml;
    env:
      SECURITY_OAUTH2_PROVIDERREQUIREMENTS_TYPE: ${OAUTH2_PROVIDER}
      SECURITY_OAUTH2_PROVIDERREQUIREMENTS_ORGANIZATION: gcp-spikers
      JAVA_OPTS: -Dlogging.level.com.netflix.spinnaker.gate.security.oauth2=DEBUG
    EOF_CONFIG
    "

    \$HAL_COMMAND config security ui edit --override-base-url http://${SPINNAKER_DOMAIN_NAME}
    \$HAL_COMMAND config security api edit --override-base-url http://${SPINNAKER_DOMAIN_NAME}/gate

    \$HAL_COMMAND config security authn oauth2 edit \
      --client-id ${OAUTH2_CLIENT_ID} \
      --client-secret ${OAUTH2_CLIENT_SECRET} \
      --provider ${OAUTH2_PROVIDER} \
      --pre-established-redirect-uri http://${SPINNAKER_DOMAIN_NAME}/gate/login

    \$HAL_COMMAND config security authn oauth2 enable

    \$HAL_COMMAND config  || true
EOF_KUBECTL
kubectl apply -f -
