#!/bin/sh

set -o errexit
set -o pipefail
set -o nounset

# Get the external cluster IP
CLUSTER_IP=$(curl -SsL --insecure https://kubernetes.default/api | jq -r '.serverAddressByClientCIDRs[0].serverAddress')

# Replace CLUSTER_IP in the rewrite filter and action file
sed -i "s/CLUSTER_IP/${CLUSTER_IP}/g" /etc/privoxy/k8s-rewrite-external.filter
sed -i "s/CLUSTER_IP/${CLUSTER_IP}/g" /etc/privoxy/k8s-only.action

# Replace CLUSTER_IP in the rewrite filter and action file
sed -i "s/KUBERNETES_SERVICE_HOST/${KUBERNETES_SERVICE_HOST}/g" /etc/privoxy/k8s-rewrite-external.filter
sed -i "s/KUBERNETES_SERVICE_HOST/${KUBERNETES_SERVICE_HOST}/g" /etc/privoxy/k8s-only.action

# Start Privoxy un-daemonized
privoxy --no-daemon /etc/privoxy/config
