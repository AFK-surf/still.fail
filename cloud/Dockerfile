FROM alpine:3.23@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0
# The iroh-relay Beijing's and Hong Kong's run, from still.fail's branch of iroh (station/native/mesh/Cargo.toml's
# iroh-relay rev; .github/workflows/relay.yml puts it in the releases bucket): a packet that waited 200 ms for a slow
# client dropped, not queued for seconds. Change it with that rev.
RUN apk add --no-cache ca-certificates curl \
    && curl --fail --location --retry 3 \
       https://app.still.fail/releases/relay/iroh-relay-a091b3326b7859ea0338240f57896f7b93406079-linux-x64 \
       -o /usr/local/bin/iroh-relay \
    && echo 'cf6c4260ee1b5e829a478f79c0911427e341bbc8d1cc161409de34c906b15957  /usr/local/bin/iroh-relay' | sha256sum -c - \
    && chmod 755 /usr/local/bin/iroh-relay \
    && apk del curl
COPY relay-entrypoint.sh /usr/local/bin/relay-entrypoint
RUN chmod 755 /usr/local/bin/relay-entrypoint && adduser -D relay
USER relay
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/relay-entrypoint"]
