FROM debian:bookworm-slim AS downloader

ARG DIGIBYTE_VERSION=9.26.7
ARG DIGIBYTE_SHA256

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl tar && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN test -n "$DIGIBYTE_SHA256" && \
    curl -fSL --retry 3 \
      -o digibyte.tar.gz \
      "https://github.com/DigiByte-Core/digibyte/releases/download/v${DIGIBYTE_VERSION}/digibyte-${DIGIBYTE_VERSION}-x86_64-linux-gnu.tar.gz" && \
    echo "${DIGIBYTE_SHA256}  digibyte.tar.gz" | sha256sum -c - && \
    mkdir -p /build/extracted && \
    tar -xzf digibyte.tar.gz -C /build/extracted && \
    find /build/extracted -type f -name digibyted \
      -exec cp {} /build/digibyted \; && \
    find /build/extracted -type f -name digibyte-cli \
      -exec cp {} /build/digibyte-cli \; && \
    test -s /build/digibyted && \
    test -s /build/digibyte-cli

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates libstdc++6 libgcc-s1 && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 1000 digibyte && \
    useradd -u 1000 -g digibyte \
      -m -s /usr/sbin/nologin digibyte && \
    mkdir -p /opt/blockchain/data \
             /opt/blockchain/config && \
    chown -R digibyte:digibyte /opt/blockchain

COPY --from=downloader /build/digibyted /usr/local/bin/
COPY --from=downloader /build/digibyte-cli /usr/local/bin/

USER digibyte

WORKDIR /opt/blockchain

VOLUME ["/opt/blockchain/data", "/opt/blockchain/config"]

EXPOSE 12024 14022

ENTRYPOINT ["digibyted"]

CMD ["-datadir=/opt/blockchain/data", "-server=1"]
