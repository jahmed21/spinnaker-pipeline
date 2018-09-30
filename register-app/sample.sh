#!/usr/bin/env bash
kubectl config use-context gke_ea-paas_australia-southeast1_ea-app-gke
kubectl --namespace kube-system delete secret reg1
kubectl --namespace kube-system create secret docker-registry reg1 --docker-server="https://asia.gcr.io" --docker-username="_json_key" --docker-password="$(cat spinnaker-gcs-access-key.json)" --docker-email=reg1@anz.com 
kubectl --namespace kube-system annotate secret reg1 ex.anz.com/repositories=ea-paas/sample-sb
kubectl --namespace kube-system label secret reg1 ex-cluster=ea-cd-gke
kubectl --namespace kube-system delete secret reg2
kubectl --namespace kube-system create secret docker-registry reg2 --docker-server="https://asia.gcr.io" --docker-username="_json_key" --docker-password="$(cat spinnaker-gcs-access-key.json)" --docker-email=reg2@anz.com 
kubectl --namespace kube-system label secret reg2 ex-cluster=ea-cd-gke
kubectl --namespace kube-system get secret
kubectl config use-context gke_ea-paas_australia-southeast1_ea-cd-gke
