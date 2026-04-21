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

umask 077
# supercronic: standard user crontab (5 fields + command); logs go to process stdout/stderr
cron_line="${CRON_SCHEDULE} /app/backup-to-telegram.sh"
printf '%s\n' "${cron_line}" >/app/crontab
chmod 600 /app/crontab

echo "Starting supercronic (schedule: ${CRON_SCHEDULE} — 5-field crontab, container TZ/UTC)."
exec /usr/local/bin/supercronic --passthrough-logs /app/crontab
