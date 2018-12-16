ARG JENKINS_SLAVE_VERSION=3.27-1
FROM jenkins/jnlp-slave:${JENKINS_SLAVE_VERSION}
ENV CLOUDSDK_CORE_DISABLE_PROMPTS=1 PATH=/opt/google-cloud-sdk/bin:$PATH
USER root
RUN set -x \
    && apt-get update -y \
    && apt-get install -y jq libapparmor-dev libseccomp-dev \
    && apt-get --purge -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*.gz \
    && curl https://sdk.cloud.google.com | bash && mv google-cloud-sdk /opt \
    && gcloud components install kubectl docker-credential-gcr gsutil beta
