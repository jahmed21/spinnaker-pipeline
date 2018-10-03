#!/usr/bin/env bash
set -xe
gsutil cp gs://ea-paas-halyard-config/spinnaker-gcs-access-key.json  .
kubectl config use-context gke_ea-paas_australia-southeast1_ea-app-gke
kubectl --namespace kube-system delete secret reg1 || true
kubectl --namespace kube-system create secret docker-registry reg1 --docker-server="https://asia.gcr.io" --docker-username="_json_key" --docker-password="$(cat spinnaker-gcs-access-key.json)" --docker-email=reg1@anz.com 
kubectl --namespace kube-system annotate secret reg1 paas.ex.anz.com/repositories=ea-paas/sample-sb
kubectl --namespace kube-system label secret reg1 paas.ex.anz.com/cluster=ea-cd-gke
kubectl --namespace kube-system delete secret reg2 || true
kubectl --namespace kube-system create secret docker-registry reg2 --docker-server="https://asia.gcr.io" --docker-username="_json_key" --docker-password="$(cat spinnaker-gcs-access-key.json)" --docker-email=reg2@anz.com 
kubectl --namespace kube-system label secret reg2 paas.ex.anz.com/cluster=ea-cd-gke
kubectl create namespace staging || true
kubectl create namespace testing || true
kubectl create namespace prod || true
kubectl --namespace kube-system get secret -l paas\.ex\.anz\.com/cluster=ea-cd-gke
kubectl config use-context gke_ea-paas_australia-southeast1_ea-cd-gke
