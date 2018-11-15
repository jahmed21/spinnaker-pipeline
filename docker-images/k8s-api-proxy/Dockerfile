FROM alpine

RUN apk add -U curl privoxy jq && \
    mv /etc/privoxy/templates /etc/privoxy-templates && \
    rm -rf /var/cache/apk/* /etc/privoxy/* && \
    mv /etc/privoxy-templates /etc/privoxy/templates

ADD --chown=privoxy:privoxy config k8s-only.action k8s-rewrite-external.filter k8s-api-proxy.sh /etc/privoxy/
EXPOSE 8118/tcp
ENTRYPOINT ["/etc/privoxy/k8s-api-proxy.sh"]
