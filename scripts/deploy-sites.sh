#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly CONFIG_FILE="${ROOT_DIR}/config/sites.yaml"
readonly DEPLOY_ROOT="/opt/backbone-infa/sites"
readonly BUILD_ROOT="${BUILD_ROOT:-/tmp/backbone-site-builds}"

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

reload_caddy() {
  if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      local compose_file="${ROOT_DIR}/docker/docker-compose.yml"
      if docker compose -f "$compose_file" ps -q caddy >/dev/null 2>&1; then
        log "🔁 Reloading Caddy (docker compose)"
        docker compose -f "$compose_file" exec -T caddy caddy reload --config /etc/caddy/Caddyfile
        return 0
      fi
    fi
    if command -v docker-compose >/dev/null 2>&1; then
      local compose_file="${ROOT_DIR}/docker/docker-compose.yml"
      if docker-compose -f "$compose_file" ps -q caddy >/dev/null 2>&1; then
        log "🔁 Reloading Caddy (docker-compose)"
        docker-compose -f "$compose_file" exec -T caddy caddy reload --config /etc/caddy/Caddyfile
        return 0
      fi
    fi
  fi
  if command -v systemctl >/dev/null 2>&1; then
    log "🔁 Reloading Caddy (systemctl)"
    systemctl reload caddy
    return 0
  fi
  log "⚠️ Unable to reload Caddy automatically"
  return 1
}

main() {
  if [[ ${EUID} -ne 0 ]]; then
    log "❌ This script must be run with sudo/root privileges."
    exit 1
  fi

  require_command git
  require_command rsync
  require_command yq
  if ! yq --version 2>&1 | grep -qi 'mikefarah'; then
    log "❌ This script expects mikefarah/yq v4+. Current version: $(yq --version 2>&1 | head -n1)"
    exit 1
  fi

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "❌ Missing configuration file: $CONFIG_FILE"
    exit 1
  fi

  mkdir -p "$DEPLOY_ROOT"
  mkdir -p "$BUILD_ROOT"

  log "🚀 Deploying sites from ${CONFIG_FILE}"
  local reload_requested=false
  local has_sites=false

  while IFS= read -r site; do
    has_sites=true
    local name domain source repo branch build_cmd output_dir local_path caddy_reload
    name="$(yq -r '.name' <<<"$site")"
    domain="$(yq -r '.domain' <<<"$site")"
    source="$(yq -r '.source' <<<"$site")"
    repo="$(yq -r '.repo // ""' <<<"$site")"
    branch="$(yq -r '.branch // "main"' <<<"$site")"
    build_cmd="$(yq -r '.build // ""' <<<"$site")"
    output_dir="$(yq -r '.output_dir // ""' <<<"$site")"
    local_path="$(yq -r '.local_path // ""' <<<"$site")"
    caddy_reload="$(yq -r '.caddy_reload // false' <<<"$site")"

    log "📦 Processing ${name} (${domain})"

    local target_dir="${DEPLOY_ROOT}/${name}"
    mkdir -p "$target_dir"

    case "$source" in
      repo)
        if [[ -z "$repo" ]]; then
          log "❌ Missing 'repo' for site ${name}"
          exit 1
        fi
        if [[ -z "$output_dir" ]]; then
          log "❌ Missing 'output_dir' for site ${name}"
          exit 1
        fi

        local repo_dir="${BUILD_ROOT}/${name}"
        if [[ -d "${repo_dir}/.git" ]]; then
          log "🏗️ Updating existing clone for ${name}"
          git -C "$repo_dir" fetch --all --prune
          git -C "$repo_dir" checkout "$branch"
          git -C "$repo_dir" pull --ff-only origin "$branch"
        else
          log "🏗️ Cloning ${repo} @ ${branch}"
          rm -rf "$repo_dir"
          git clone --branch "$branch" "$repo" "$repo_dir"
        fi

        if [[ -n "$build_cmd" && "$build_cmd" != "null" ]]; then
          log "🏗️ Running build command for ${name}: ${build_cmd}"
          (cd "$repo_dir" && eval "$build_cmd")
        fi

        local source_dir="${repo_dir}/${output_dir}"
        if [[ ! -d "$source_dir" ]]; then
          log "❌ Build output not found: ${source_dir}"
          exit 1
        fi

        log "📦 Syncing artifacts to ${target_dir}"
        rsync -a --delete "$source_dir/" "$target_dir/"
        ;;
      local)
        if [[ -z "$local_path" ]]; then
          log "❌ Missing 'local_path' for site ${name}"
          exit 1
        fi
        local abs_local_path
        abs_local_path="${local_path}"
        if [[ ! "$abs_local_path" = /* ]]; then
          abs_local_path="${ROOT_DIR}/${local_path}"
        fi
        if [[ ! -d "$abs_local_path" ]]; then
          log "❌ Local path not found: ${abs_local_path}"
          exit 1
        fi
        log "📦 Syncing local files from ${abs_local_path}"
        rsync -a --delete "$abs_local_path/" "$target_dir/"
        ;;
      *)
        log "❌ Unsupported source '${source}' for site ${name}"
        exit 1
        ;;
    esac

    log "✅ Setting ownership to www-data:www-data"
    chown -R www-data:www-data "$target_dir"

    if [[ "$caddy_reload" == "true" ]]; then
      reload_requested=true
    fi
  done < <(yq eval -o=json -I=0 '.sites // [] | .[]' "$CONFIG_FILE")

  if [[ "$has_sites" == false ]]; then
    log "⚠️ No sites defined. Nothing to do."
    exit 0
  fi

  if [[ "$reload_requested" == true ]]; then
    reload_caddy || log "⚠️ Caddy reload reported an issue"
  fi

  log "✅ All sites processed"
}

main "$@"
