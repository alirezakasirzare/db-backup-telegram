FROM alpine:3.21

ARG SUPERCRONIC_VERSION=0.2.33
# Set automatically with BuildKit; default amd64 for plain `docker build`
ARG TARGETARCH=amd64

RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    curl \
    docker-cli \
    gzip \
    sed \
    && SC_ARCH="${TARGETARCH:-amd64}" \
    && case "${SC_ARCH}" in \
         amd64) SC_FILE=supercronic-linux-amd64; SC_SHA1=71b0d58cc53f6bd72cf2f293e09e294b79c666d8 ;; \
         arm64) SC_FILE=supercronic-linux-arm64; SC_SHA1=e0f0c06ebc5627e43b25475711e694450489ab00 ;; \
         *) echo "Unsupported TARGETARCH=${SC_ARCH} (use amd64 or arm64)" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/${SC_FILE}" -o "/tmp/${SC_FILE}" \
    && echo "${SC_SHA1}  /tmp/${SC_FILE}" | sha1sum -c - \
    && mv "/tmp/${SC_FILE}" /usr/local/bin/supercronic \
    && chmod +x /usr/local/bin/supercronic

COPY backup-to-telegram.sh /app/backup-to-telegram.sh
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /app/backup-to-telegram.sh /docker-entrypoint.sh \
    && mkdir -p /app

WORKDIR /app

ENV CRON_SCHEDULE="0 2 * * *"

ENTRYPOINT ["/docker-entrypoint.sh"]
