FROM alpine:latest AS ariang

ARG ARIANG_VERSION=1.3.15

RUN apk add --no-cache ca-certificates curl unzip \
    && curl -fsSL -o /tmp/ariang.zip \
        "https://github.com/mayswind/AriaNg/releases/download/${ARIANG_VERSION}/AriaNg-${ARIANG_VERSION}.zip" \
    && mkdir -p /out \
    && unzip -q /tmp/ariang.zip -d /out \
    && rm -f /tmp/ariang.zip

FROM alpine:latest

ARG VERSION=dev

LABEL org.opencontainers.image.title="aria2-ariang" \
      org.opencontainers.image.description="aria2 + AriaNg web UI served by althttpd on Alpine Linux" \
      org.opencontainers.image.version="${VERSION}"

RUN apk add --no-cache \
        aria2 \
        althttpd \
        ca-certificates \
        curl \
        su-exec

COPY --from=ariang /out /usr/share/aria2-ariang/web
COPY aria2.conf /etc/aria2/aria2.conf
COPY entrypoint.sh healthcheck.sh /usr/local/bin/
COPY jsonrpc /usr/local/share/aria2-ariang/jsonrpc

RUN chmod 0755 \
        /usr/local/bin/entrypoint.sh \
        /usr/local/bin/healthcheck.sh \
        /usr/local/share/aria2-ariang/jsonrpc \
    && addgroup -g 1000 aria2 \
    && adduser -D -u 1000 -G aria2 -h /aria2 aria2 \
    && mkdir -p /aria2/data /aria2/conf /www \
    && chown -R aria2:aria2 /aria2 /www

EXPOSE 8080
VOLUME ["/aria2/data", "/aria2/conf"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--conf-path=/aria2/conf/aria2.conf"]
