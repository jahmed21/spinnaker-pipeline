FROM golang:1.8
ADD . /go/src/hello-app
RUN go install hello-app

FROM gcr.io/cloud-builders/kubectl
COPY --from=0 /go/bin/hello-app /tmp/
RUN chmod +x /tmp/hello-app \
    && apt-get update \
    && apt-get install -y iproute2 dnsutils \
    && apt-get -y autoremove \
    && apt-get clean
ENV PORT 8080
EXPOSE 8080
ENTRYPOINT []
CMD ["/tmp/hello-app"]
