#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT_DIR
readonly COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.yml"
readonly ENV_FILE="${ROOT_DIR}/docker/.env"
readonly DB_CONTAINER="backbone-umami-db"

BACKUP_DIR="${BACKUP_DIR:-/opt/backbone-infa/backups/umami}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
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
Usage: BACKUP_PASSPHRASE='...' bash scripts/backup-umami-db.sh

Optional env:
  BACKUP_DIR=/opt/backbone-infa/backups/umami
  RETENTION_DAYS=14
USAGE
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_command docker
  require_command openssl
  require_command gzip
  require_command find

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

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR" || true

  local timestamp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  local base_name="umami-db-${timestamp}.sql.gz"
  local plain_file="${BACKUP_DIR}/${base_name}"
  local encrypted_file="${plain_file}.enc"

  log "💾 Creating PostgreSQL dump from ${DB_CONTAINER}"
  docker exec "$DB_CONTAINER" sh -lc 'PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}"' \
    | gzip -c >"$plain_file"

  log "🔐 Encrypting backup"
  openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
    -pass "pass:${BACKUP_PASSPHRASE}" \
    -in "$plain_file" \
    -out "$encrypted_file"

  rm -f "$plain_file"
  chmod 600 "$encrypted_file" || true

  log "🧹 Pruning backups older than ${RETENTION_DAYS} days"
  find "$BACKUP_DIR" -type f -name 'umami-db-*.sql.gz.enc' -mtime "+${RETENTION_DAYS}" -delete

  log "✅ Backup created: ${encrypted_file}"
}

main "$@"
