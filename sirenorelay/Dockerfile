ARG BUILD_VERSION
ARG BUILD_ARCH
ARG SIRENORELAY_VERSION=1.5.0
ARG HIMALAYA_VERSION=2.2.1

FROM node:22-bookworm-slim AS monaco

RUN npm install --prefix /opt/monaco monaco-editor@0.55.1

FROM debian:bookworm-slim

ARG BUILD_VERSION
ARG BUILD_ARCH
ARG TARGETARCH
ARG SIRENORELAY_VERSION
ARG HIMALAYA_VERSION

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl jq nginx procps python3 socat util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && arch="${BUILD_ARCH:-$TARGETARCH}" \
    && case "$arch" in \
      amd64) sireno_arch=amd64; himalaya_arch=x86_64; ttyd_arch=x86_64 ;; \
      aarch64|arm64) sireno_arch=arm64; himalaya_arch=aarch64; ttyd_arch=aarch64 ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/sergiocarracedo/sireno-relay/releases/download/v${SIRENORELAY_VERSION}/sirenorelay_${SIRENORELAY_VERSION}_linux_${sireno_arch}.tar.gz" -o /tmp/sirenorelay.tgz \
    && tar -xzf /tmp/sirenorelay.tgz -C /usr/local/bin sirenorelay \
    && rm /tmp/sirenorelay.tgz \
    && curl -fsSL "https://github.com/pimalaya/himalaya/releases/download/v${HIMALAYA_VERSION}/himalaya.${himalaya_arch}-linux.tgz" -o /tmp/himalaya.tgz \
    && tar -xzf /tmp/himalaya.tgz -C /usr/local/bin himalaya \
    && rm /tmp/himalaya.tgz \
    && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${ttyd_arch}" -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd \
    && groupadd --gid 10001 sirenorelay \
    && useradd --uid 10001 --gid 10001 --home-dir /data/sirenorelay --create-home --shell /bin/bash sirenorelay \
    && sirenorelay version \
    && himalaya --version

COPY addon-run.sh sirenorelay-terminal.sh sirenorelay-onboard.sh web.py /usr/local/bin/
COPY ingress.conf /etc/nginx/sirenorelay-ingress.conf
COPY web /usr/share/sirenorelay-web/
COPY logo.png /usr/share/sirenorelay-web/logo.png
COPY --from=monaco /opt/monaco/node_modules/monaco-editor/min/vs /usr/share/sirenorelay-web/vs/
RUN chmod +x /usr/local/bin/addon-run.sh /usr/local/bin/sirenorelay-terminal.sh /usr/local/bin/sirenorelay-onboard.sh

LABEL io.hass.version="${BUILD_VERSION}" \
      io.hass.type="addon" \
      io.hass.arch="${BUILD_ARCH}"

CMD ["/usr/local/bin/addon-run.sh"]
