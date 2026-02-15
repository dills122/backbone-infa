#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT_DIR
readonly CRON_FILE="/etc/cron.d/backbone-umami-backup"
readonly ENV_FILE="/etc/backbone/umami-backup.env"

BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-}"
BACKUP_DIR="${BACKUP_DIR:-/opt/backbone-infa/backups/umami}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
CRON_SCHEDULE="${CRON_SCHEDULE:-17 3 * * *}"
RUN_NOW="${RUN_NOW:-false}"

log() {
  echo "$*"
}

usage() {
  cat <<'USAGE'
Usage: sudo BACKUP_PASSPHRASE='...' bash scripts/install-umami-backup-cron.sh

Optional env:
  BACKUP_DIR=/opt/backbone-infa/backups/umami
  RETENTION_DAYS=14
  CRON_SCHEDULE='17 3 * * *'
  RUN_NOW=true
USAGE
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ $EUID -ne 0 ]]; then
    log "❌ Must run as root."
    exit 1
  fi
  if [[ -z "$BACKUP_PASSPHRASE" ]]; then
    log "❌ BACKUP_PASSPHRASE is required."
    exit 1
  fi

  install -d -m 700 /etc/backbone
  cat >"$ENV_FILE" <<EOF
BACKUP_PASSPHRASE=${BACKUP_PASSPHRASE}
BACKUP_DIR=${BACKUP_DIR}
RETENTION_DAYS=${RETENTION_DAYS}
EOF
  chmod 600 "$ENV_FILE"

  cat >"$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${CRON_SCHEDULE} root . ${ENV_FILE} && bash ${ROOT_DIR}/scripts/backup-umami-db.sh >> /var/log/backbone-umami-backup.log 2>&1
EOF
  chmod 644 "$CRON_FILE"

  log "✅ Installed cron backup schedule: ${CRON_SCHEDULE}"
  log "   Config: ${ENV_FILE}"
  log "   Cron:   ${CRON_FILE}"

  if [[ "$RUN_NOW" == "true" ]]; then
    log "🚀 Running first backup now"
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    bash "${ROOT_DIR}/scripts/backup-umami-db.sh"
  fi
}

main "$@"
