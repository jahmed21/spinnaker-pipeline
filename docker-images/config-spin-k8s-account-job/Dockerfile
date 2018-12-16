ARG PROJECT_ID
ARG HELM_VERSION=v2.12.0
FROM asia.gcr.io/${PROJECT_ID}/cloud-builders-community-helm:${HELM_VERSION}

ARG BUILD_DATE
ARG COMMIT_SHA
ARG ROER_VERSION=v0.11.3

LABEL maintainer="manikandan.natarajan@anz.com" \
      org.label-schema.vcs-ref=$COMMIT_SHA \
      org.label-schema.build-date=$BUILD_DATE

COPY job.sh /builder/

RUN chmod +x /builder/job.sh

ENTRYPOINT ["/builder/job.sh"]
