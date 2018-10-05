#!/usr/bin/env bash
set -xe
gsutil cp gs://app-service-12-config/gcr-sa-key.json key.json
kubectl config use-context gke_app-service-12_australia-southeast1_ea-app-gke
kubectl --namespace kube-system delete secret reg1 || true
kubectl --namespace kube-system create secret docker-registry reg1 --docker-server="https://asia.gcr.io" --docker-username="_json_key" --docker-password="$(cat key.json)" --docker-email=reg1@anz.com 
kubectl --namespace kube-system annotate secret reg1 paas.ex.anz.com/repositories=app-service-12/sample-sb
kubectl --namespace kube-system label secret reg1 paas.ex.anz.com/cluster=ea-cd-gke
kubectl --namespace kube-system label secret reg1 paas.ex.anz.com/project=cd-pipeline-1
kubectl create namespace staging || true
kubectl create namespace testing || true
kubectl create namespace prod || true
kubectl --namespace kube-system get secret -l paas\.ex\.anz\.com/cluster=ea-cd-gke
kubectl config use-context gke_cd-pipeline-1_australia-southeast1_ea-cd-gke
