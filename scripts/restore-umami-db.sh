#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT_DIR
readonly COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.yml"
readonly ENV_FILE="${ROOT_DIR}/docker/.env"
readonly DB_CONTAINER="backbone-umami-db"
readonly APP_SERVICE="umami"

BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-}"

log() {
  echo "$*"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "❌ Missing dependency: $cmd"
    exit 1
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash scripts/restore-umami-db.sh --file <backup.sql.gz.enc> [--drop-existing] [--keep-app-running]
USAGE
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

main() {
  local backup_file=""
  local drop_existing=false
  local keep_app_running=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        backup_file="${2:-}"
        shift 2
        ;;
      --drop-existing)
        drop_existing=true
        shift
        ;;
      --keep-app-running)
        keep_app_running=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log "❌ Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  require_command docker
  require_command openssl
  require_command gunzip

  if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
    log "❌ Valid --file path is required."
    exit 1
  fi
  if [[ -z "$BACKUP_PASSPHRASE" ]]; then
    log "❌ BACKUP_PASSPHRASE is required."
    exit 1
  fi

  if [[ ! -f "$COMPOSE_FILE" || ! -f "$ENV_FILE" ]]; then
    log "❌ Missing compose or env file."
    exit 1
  fi

  if ! compose ps --status=running --services | grep -Fxq "umami-db"; then
    log "❌ umami-db is not running."
    exit 1
  fi

  local app_was_running=false
  if compose ps --status=running --services | grep -Fxq "$APP_SERVICE"; then
    app_was_running=true
  fi

  if [[ "$keep_app_running" == false && "$app_was_running" == true ]]; then
    log "⏸️ Stopping Umami app during restore"
    compose stop "$APP_SERVICE"
  fi

  if [[ "$drop_existing" == true ]]; then
    log "🧨 Dropping existing public schema before restore"
    docker exec "$DB_CONTAINER" sh -lc 'PGPASSWORD="${POSTGRES_PASSWORD}" psql -U "${POSTGRES_USER}" "${POSTGRES_DB}" -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;"'
  fi

  log "♻️ Restoring database from encrypted backup"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
    -pass "pass:${BACKUP_PASSPHRASE}" \
    -in "$backup_file" \
    | gunzip -c \
    | docker exec -i "$DB_CONTAINER" sh -lc 'PGPASSWORD="${POSTGRES_PASSWORD}" psql -U "${POSTGRES_USER}" "${POSTGRES_DB}"'

  if [[ "$keep_app_running" == false && "$app_was_running" == true ]]; then
    log "▶️ Starting Umami app"
    compose up -d "$APP_SERVICE"
  fi

  log "✅ Restore complete"
}

main "$@"
