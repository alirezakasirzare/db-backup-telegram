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

# Do not `source` .env: lines like CRON_SCHEDULE=0 2 * * * make the shell run extra words
# and glob `*` to filenames in /app (e.g. backup-to-telegram.sh).
cron_line_raw="$(grep -E '^[[:space:]]*CRON_SCHEDULE=' /app/.env 2>/dev/null | tail -n1 || true)"
file_cron=""
if [[ -n "${cron_line_raw}" ]]; then
  file_cron="${cron_line_raw#*=}"
  file_cron="${file_cron%$'\r'}"
  if [[ "${file_cron}" =~ ^\"(.*)\"$ ]]; then
    file_cron="${BASH_REMATCH[1]}"
  elif [[ "${file_cron}" =~ ^\'(.*)\'$ ]]; then
    file_cron="${BASH_REMATCH[1]}"
  fi
fi
if [[ -n "${file_cron}" ]]; then
  CRON_SCHEDULE="${file_cron}"
else
  CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"
fi

mkdir -p /etc/crontabs
umask 077
cron_line="${CRON_SCHEDULE} /app/backup-to-telegram.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
printf '%s\n' "${cron_line}" >/etc/crontabs/root
chmod 600 /etc/crontabs/root

echo "Starting dcron in foreground (schedule: ${CRON_SCHEDULE} UTC fields — standard 5-field crontab)."
exec /usr/sbin/crond -f -l 8
