#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly CONFIG_FILE="${ROOT_DIR}/config/sites.yaml"
readonly DEPLOY_ROOT="/opt/backbone-infa/sites"

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

last_modified() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "n/a"
    return
  fi

  if stat -c '%y' "$path" >/dev/null 2>&1; then
    stat -c '%y' "$path"
    return
  fi

  if stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$path" >/dev/null 2>&1; then
    stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$path"
    return
  fi

  echo "unknown"
}

main() {
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

  log "🚀 Checking configured sites"
  local has_sites=false

  while IFS= read -r site; do
    has_sites=true
    local name domain source local_path status_emoji checked_path mtime
    name="$(yq -r '.name' <<<"$site")"
    domain="$(yq -r '.domain' <<<"$site")"
    source="$(yq -r '.source' <<<"$site")"
    local_path="$(yq -r '.local_path // ""' <<<"$site")"

    case "$source" in
      local)
        if [[ -z "$local_path" ]]; then
          checked_path="n/a"
          status_emoji="❌"
        else
          if [[ "$local_path" != /* ]]; then
            checked_path="${ROOT_DIR}/${local_path}"
          else
            checked_path="$local_path"
          fi
          if [[ -d "$checked_path" ]]; then
            status_emoji="✅"
          else
            status_emoji="❌"
          fi
        fi
        ;;
      repo)
        checked_path="${DEPLOY_ROOT}/${name}"
        if [[ -d "$checked_path" ]]; then
          status_emoji="✅"
        else
          status_emoji="❌"
        fi
        ;;
      *)
        checked_path="unknown"
        status_emoji="❌"
        ;;
    esac

    if [[ "$checked_path" != "n/a" && "$checked_path" != "unknown" ]]; then
      mtime="$(last_modified "$checked_path")"
    else
      mtime="n/a"
    fi

    log "📦 ${name}"
    log "   Domain: ${domain}"
    log "   Source: ${source}"
    log "   Path: ${checked_path} ${status_emoji}"
    log "   Last modified: ${mtime}"
  done < <(yq eval -o=json -I=0 '.sites // [] | .[]' "$CONFIG_FILE")

  if [[ "$has_sites" == false ]]; then
    log "⚠️ No sites defined."
    return 0
  fi
}

main "$@"
