ARG PROJECT_ID
ARG HELM_VERSION=v2.12.0

FROM asia.gcr.io/${PROJECT_ID}/cloud-builders-community-helm:${HELM_VERSION}

ARG BUILD_DATE
ARG COMMIT_SHA
ARG ROER_VERSION=v0.11.3

LABEL maintainer="manikandan.natarajan@anz.com" \
      org.label-schema.vcs-ref=$COMMIT_SHA \
      org.label-schema.build-date=$BUILD_DATE

COPY app.yml spin-cli.sh roer-${ROER_VERSION}.sha256 /builder/

RUN set -ex \
    && curl -sSflL https://github.com/spinnaker/roer/releases/download/${ROER_VERSION}/roer-linux-amd64 \
              | tee /usr/local/bin/roer \
              | sha256sum -c /builder/roer-${ROER_VERSION}.sha256 \
    && chmod +x /usr/local/bin/roer /builder/spin-cli.sh \
    && SPINNAKER_API=nothing roer --version

ENTRYPOINT ["/builder/spin-cli.sh"]
