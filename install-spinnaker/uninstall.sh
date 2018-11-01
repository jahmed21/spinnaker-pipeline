#!/usr/bin/env bash

set -xeu

_HELM_RELEASE_NAME=$1
SPINNAKER_NS=spinnaker

# now delete the release objects
kubectl --namespace ${SPINNAKER_NS} delete all,deployment,configmap,secret,serviceaccount,rolebinding,clusterrolebinding -l release="${_HELM_RELEASE_NAME}" 

# now delete the running jobs,pods
kubectl --namespace ${SPINNAKER_NS} delete job,pod,deployment --all 

# now delete the tillerless storage
kubectl --namespace kube-system delete secret -l NAME="${_HELM_RELEASE_NAME}" 
