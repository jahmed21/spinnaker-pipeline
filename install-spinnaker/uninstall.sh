#!/usr/bin/env bash

set -xeu

_HELM_RELEASE_NAME=$1
SPINNAKER_NS=spinnaker

# now delete the CRB
kubectl delete clusterrolebinding -l release="${_HELM_RELEASE_NAME}" 

# now delete the release objects
kubectl --namespace ${SPINNAKER_NS} delete all,configmap,secret,serviceaccount,rolebinding,clusterrolebinding -l release="${_HELM_RELEASE_NAME}" 

# now delete the running jobs,pods
kubectl --namespace ${SPINNAKER_NS} delete job,pod --all 

# now delete the tillerless storage
if kubectl --namespace kube-system get secret "${_HELM_RELEASE_NAME}.v1" -o=jsonpath='{.metadata.name}' 2>/dev/null; then
  kubectl --namespace kube-system delete secret "${_HELM_RELEASE_NAME}.v1" 
fi
