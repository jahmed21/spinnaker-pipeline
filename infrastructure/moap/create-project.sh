#!/bin/bash

set -xeuo pipefail

PROJECT_ID=$1
gcloud projects create $PROJECT_ID

gcloud beta billing projects link $PROJECT_ID \
  --billing-account=$(gcloud beta billing  accounts list   --format="value(name)" --filter open=true)

SA_NAME=terraform
gcloud --project=$PROJECT_ID iam service-accounts create $SA_NAME --display-name=$SA_NAME
SA_EMAIL=$(gcloud --project=$PROJECT_ID iam service-accounts list --format="value(email)" --filter displayName=terraform)

gcloud projects add-iam-policy-binding $PROJECT_ID --role roles/owner --member serviceAccount:$SA_EMAIL

gcloud --project=$PROJECT_ID iam service-accounts keys create terraform-${PROJECT_ID}.json --iam-account=$SA_EMAIL
gcloud --project $PROJECT_ID services enable iam.googleapis.com
gcloud --project $PROJECT_ID services enable cloudresourcemanager.googleapis.com
gcloud --project $PROJECT_ID services enable cloudbuild.googleapis.com
gcloud --project $PROJECT_ID services enable compute.googleapis.com
gcloud --project $PROJECT_ID services enable container.googleapis.com
gcloud --project $PROJECT_ID services enable pubsub.googleapis.com
