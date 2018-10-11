#!/bin/bash

set -xe

gcloud --project $1 services enable iam.googleapis.com
gcloud --project $1 services enable cloudresourcemanager.googleapis.com
gcloud --project $1 services enable cloudbuild.googleapis.com
#gcloud --project $1 services enable compute.googleapis.com
#gcloud --project $1 services enable container.googleapis.com
#gcloud --project $1 services enable pubsub.googleapis.com
