FROM alpine:3.21

RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    curl \
    dcron \
    docker-cli \
    gzip \
    sed

COPY backup-to-telegram.sh /app/backup-to-telegram.sh
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /app/backup-to-telegram.sh /docker-entrypoint.sh \
    && mkdir -p /app /etc/crontabs

WORKDIR /app

# Optional override when not set in mounted .env
ENV CRON_SCHEDULE="0 2 * * *"

ENTRYPOINT ["/docker-entrypoint.sh"]
