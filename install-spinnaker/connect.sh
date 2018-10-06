#!/usr/bin/env bash
set -xeo pipefail

if _prevPID="$(ps -eo "pid,command" | grep '[k]ubectl port-forward --namespace spinnaker' | sed "s/^\s*//" | cut -f1 -d ' ' )"; then
  echo "Killing $_prevPID"
  kill $_prevPID
fi

kubectl port-forward --namespace spinnaker $(kubectl get pods --namespace spinnaker -l "cluster=spin-deck" -o jsonpath="{.items[0].metadata.name}") 9000 > /dev/null  &
kubectl port-forward --namespace spinnaker $(kubectl get pods --namespace spinnaker -l "cluster=spin-gate" -o jsonpath="{.items[0].metadata.name}") 8084 > /dev/null  &
