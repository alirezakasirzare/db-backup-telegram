#!/usr/bin/env bash
# PostgreSQL backups from Docker containers -> Telegram (sendDocument).
# Requires: bash, docker, curl, gzip, date, wc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Create it from the template in the repo." >&2
  exit 1
fi

# Load .env without `source` so values like CRON_SCHEDULE=0 2 * * * are not re-parsed by the shell.
load_env_file() {
  local env_file="$1" raw_line line key val
  while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
    line="${raw_line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      if [[ "${val}" =~ ^\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
      elif [[ "${val}" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi
      printf -v "${key}" '%s' "${val}"
      export "${key}"
    fi
  done < "${env_file}"
}

load_env_file "${ENV_FILE}"

: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN in .env}"
: "${TELEGRAM_CHAT_ID:?Set TELEGRAM_CHAT_ID in .env}"
: "${BACKUP_TARGETS:?Set BACKUP_TARGETS in .env (see comments in .env)}"

BACKUP_DIR="${BACKUP_DIR:-/tmp/pg-telegram-backups}"
DELETE_LOCAL_AFTER_SEND="${DELETE_LOCAL_AFTER_SEND:-true}"

mkdir -p "${BACKUP_DIR}"

ts="$(date -u +"%Y%m%dT%H%M%SZ")"
failures=0

send_to_telegram() {
  local file_path="$1"
  local caption="$2"
  local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument"

  curl -fsS -X POST "${url}" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "document=@${file_path}" \
    -F "caption=${caption}" \
    -F "disable_notification=true" \
    >/dev/null
}

IFS=',' read -r -a targets <<< "${BACKUP_TARGETS}"
for raw in "${targets[@]}"; do
  spec="$(echo "${raw}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "${spec}" ]] && continue

  IFS=':' read -r container db user <<< "${spec}"
  container="$(echo "${container}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  db="$(echo "${db}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  user="$(echo "${user}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [[ -z "${container}" || -z "${db}" || -z "${user}" ]]; then
    echo "Skip invalid target (need container:database:user): ${spec}" >&2
    failures=$((failures + 1))
    continue
  fi

  if ! docker inspect "${container}" >/dev/null 2>&1; then
    echo "Docker container not found: ${container}" >&2
    failures=$((failures + 1))
    continue
  fi

  safe_name="$(echo "${container}_${db}" | tr '/:' '__')"
  out="${BACKUP_DIR}/${safe_name}_${ts}.sql.gz"
  caption="${container} / ${db} @ ${ts} UTC"

  echo "Dumping ${db} from ${container} (user ${user}) -> ${out}"

  if [[ -n "${POSTGRES_PASSWORD:-}" ]]; then
    dump_cmd=(docker exec -e "PGPASSWORD=${POSTGRES_PASSWORD}" "${container}" pg_dump -U "${user}" -d "${db}" --no-owner --no-acl)
  else
    dump_cmd=(docker exec "${container}" pg_dump -U "${user}" -d "${db}" --no-owner --no-acl)
  fi

  if ! "${dump_cmd[@]}" | gzip -9 > "${out}"; then
    echo "pg_dump failed for ${container}:${db}" >&2
    rm -f "${out}" 2>/dev/null || true
    failures=$((failures + 1))
    continue
  fi

  if [[ ! -s "${out}" ]]; then
    echo "Empty dump file for ${container}:${db}" >&2
    rm -f "${out}" 2>/dev/null || true
    failures=$((failures + 1))
    continue
  fi

  # Telegram Bot API document limit is 50 MiB (https://core.telegram.org/bots/api#sending-files)
  max_bytes=$((50 * 1024 * 1024))
  size="$(wc -c < "${out}")"
  size=$((size + 0))
  if [[ "${size}" -gt "${max_bytes}" ]]; then
    echo "Dump ${out} is ${size} bytes; Telegram limit is ${max_bytes}. Skipping upload." >&2
    failures=$((failures + 1))
    continue
  fi

  echo "Uploading to Telegram..."
  if ! send_to_telegram "${out}" "${caption}"; then
    echo "Telegram upload failed for ${out}" >&2
    failures=$((failures + 1))
    continue
  fi

  if [[ "${DELETE_LOCAL_AFTER_SEND}" == "true" || "${DELETE_LOCAL_AFTER_SEND}" == "1" ]]; then
    rm -f "${out}"
  fi

  echo "Done: ${container}:${db}"
done

if [[ "${failures}" -gt 0 ]]; then
  echo "Completed with ${failures} failure(s)." >&2
  exit 1
fi

echo "All backups finished successfully."
