#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /app/.env ]]; then
  echo "Missing /app/.env — mount your config: -v /path/.env:/app/.env:ro" >&2
  exit 1
fi

if [[ ! -S /var/run/docker.sock ]]; then
  echo "Missing Docker socket — mount the host socket: -v /var/run/docker.sock:/var/run/docker.sock" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source /app/.env
set +a

CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"

mkdir -p /etc/crontabs
umask 077
cron_line="${CRON_SCHEDULE} /app/backup-to-telegram.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
printf '%s\n' "${cron_line}" >/etc/crontabs/root
chmod 600 /etc/crontabs/root

echo "Starting dcron in foreground (schedule: ${CRON_SCHEDULE} UTC fields — standard 5-field crontab)."
exec /usr/sbin/crond -f -l 8
