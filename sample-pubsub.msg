2018-10-06 08:32:33.269 DEBUG 1 --- [      Thread-16] c.n.s.e.p.google.GooglePubsubSubscriber  : Received Google pub/sub message with payload: {
  "kind": "storage#object",
  "id": "pipeline-integration-app-service-12/manifests/deploy.yml/1538814751665521",
  "selfLink": "https://www.googleapis.com/storage/v1/b/pipeline-integration-app-service-12/o/manifests%2Fdeploy.yml",
  "name": "manifests/deploy.yml",
  "bucket": "pipeline-integration-app-service-12",
  "generation": "1538814751665521",
  "metageneration": "1",
  "contentType": "application/octet-stream",
  "timeCreated": "2018-10-06T08:32:31.664Z",
  "updated": "2018-10-06T08:32:31.664Z",
  "storageClass": "REGIONAL",
  "timeStorageClassUpdated": "2018-10-06T08:32:31.664Z",
  "size": "950",
  "md5Hash": "uD9gHkQXad4MbyDT8kvB7g==",
  "mediaLink": "https://www.googleapis.com/download/storage/v1/b/pipeline-integration-app-service-12/o/manifests%2Fdeploy.yml?generation=1538814751665521&alt=media",
  "contentLanguage": "en",
  "crc32c": "H8Rqfw==",
  "etag": "CPHal9Wz8d0CEAE="
}

 and attributes: {objectGeneration=1538814751665521, eventTime=2018-10-06T08:32:31.664910Z, eventType=OBJECT_FINALIZE, payloadFormat=JSON_API_V1, notificationConfig=projects/_/buckets/pipeline-integration-app-service-12/notificationConfigs/1, bucketId=pipeline-integration-app-service-12, objectId=manifests/deploy.yml}
2018-10-06 08:32:33.413  INFO 1 --- [      Thread-16] c.n.s.e.p.google.GooglePubsubSubscriber  : artifacts Artifact(type=gcs/object, name=gs://pipeline-integration-app-service-12/manifests/deploy.yml, version=null, location=null, reference=gs://pipeline-integration-app-service-12/manifests/deploy.yml, metadata=null, artifactAccount=null, provenance=null, uuid=null)
