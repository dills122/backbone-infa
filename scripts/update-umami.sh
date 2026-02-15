#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT_DIR
readonly COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.yml"
readonly ENV_FILE="${ROOT_DIR}/docker/.env"
readonly DEFAULT_UMAMI_IMAGE="ghcr.io/umami-software/umami:postgresql-latest"
readonly SERVICE_NAME="umami"

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
Usage: scripts/update-umami.sh [--image <ref>] [--skip-probe]

Options:
  --image <ref>   Update to a specific image ref (tag or digest).
  --skip-probe    Skip HTTP probe through localhost/Caddy.
  -h, --help      Show this help.
USAGE
}

set_env_key() {
  local key="$1"
  local value="$2"
  if grep -Eq "^${key}=" "$ENV_FILE"; then
    sed -i.bak -E "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
  fi
  rm -f "${ENV_FILE}.bak"
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

current_umami_host() {
  awk '
    /^\s*#/ {next}
    /^\s*$/ {next}
    /\{/ {host=$1; gsub(/\{/, "", host)}
    /reverse_proxy[[:space:]]+backbone-umami:3000/ {print host; exit}
  ' "$ROOT_DIR/docker/Caddyfile"
}

probe_umami() {
  local host="$1"
  local attempts=20
  local i

  if [[ -z "$host" ]]; then
    log "⚠️ Unable to infer Umami host from docker/Caddyfile, skipping HTTP probe"
    return 0
  fi

  log "🔍 Probing Umami via Caddy: http://127.0.0.1/ (Host: ${host})"
  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS --max-time 5 -H "Host: ${host}" "http://127.0.0.1/" >/dev/null 2>&1; then
      log "✅ Probe passed"
      return 0
    fi
    sleep 3
  done

  return 1
}

main() {
  local target_image="$DEFAULT_UMAMI_IMAGE"
  local do_probe=true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image)
        target_image="${2:-}"
        if [[ -z "$target_image" ]]; then
          log "❌ --image requires a value"
          exit 1
        fi
        shift 2
        ;;
      --skip-probe)
        do_probe=false
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
  require_command sed
  require_command curl

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    log "❌ Missing compose file: $COMPOSE_FILE"
    exit 1
  fi
  if [[ ! -f "$ENV_FILE" ]]; then
    log "❌ Missing env file: $ENV_FILE"
    exit 1
  fi

  if ! compose ps --status=running --services | grep -Fxq "$SERVICE_NAME"; then
    log "❌ Service '${SERVICE_NAME}' is not running. Start the stack first."
    exit 1
  fi

  local previous_image
  previous_image="$(grep -E '^UMAMI_IMAGE=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$previous_image" ]]; then
    previous_image="$DEFAULT_UMAMI_IMAGE"
  fi

  log "⬇️ Pulling target image: $target_image"
  docker pull "$target_image"

  local resolved_target
  resolved_target="$(docker image inspect --format '{{index .RepoDigests 0}}' "$target_image" 2>/dev/null || true)"
  if [[ -z "$resolved_target" ]]; then
    resolved_target="$target_image"
  fi

  log "📝 Setting UMAMI_IMAGE=${resolved_target}"
  set_env_key "UMAMI_IMAGE" "$resolved_target"

  log "🚀 Restarting Umami with updated image"
  if ! compose up -d --no-deps "$SERVICE_NAME"; then
    log "❌ Update failed during compose up. Rolling back UMAMI_IMAGE=${previous_image}"
    set_env_key "UMAMI_IMAGE" "$previous_image"
    compose up -d --no-deps "$SERVICE_NAME" || true
    exit 1
  fi

  local container_state
  container_state="$(docker inspect -f '{{.State.Status}}' backbone-umami 2>/dev/null || true)"
  if [[ "$container_state" != "running" ]]; then
    log "❌ Umami container is not running after update. Rolling back."
    set_env_key "UMAMI_IMAGE" "$previous_image"
    compose up -d --no-deps "$SERVICE_NAME" || true
    exit 1
  fi

  if [[ "$do_probe" == true ]]; then
    local host
    host="$(current_umami_host || true)"
    if ! probe_umami "$host"; then
      log "❌ HTTP probe failed. Rolling back UMAMI_IMAGE=${previous_image}"
      set_env_key "UMAMI_IMAGE" "$previous_image"
      compose up -d --no-deps "$SERVICE_NAME" || true
      exit 1
    fi
  fi

  log "✅ Umami updated successfully"
  log "   Previous image: ${previous_image}"
  log "   Current image:  ${resolved_target}"
}

main "$@"
