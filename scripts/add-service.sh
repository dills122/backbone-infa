#!/usr/bin/env bash
# Updated: Generates Compose and Caddy snippets for onboarding a new service.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/templates/service-template"
SERVICES_DIR="${REPO_ROOT}/services"
CADDY_SITES_DIR="${REPO_ROOT}/docker/sites"

usage() {
  cat <<'USAGE'
Usage: scripts/add-service.sh <service-name> <domain> [internal-port]

Arguments:
  service-name   Slug for the service (letters, numbers, and dashes).
  domain         Fully qualified domain handled by Caddy for the service.
  internal-port  Container port exposed to the backbone network (default: 3000).
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

SERVICE_NAME="${1}"
SERVICE_DOMAIN="${2}"
SERVICE_PORT="${3:-3000}"

if [[ ! "${SERVICE_NAME}" =~ ^[a-z0-9-]+$ ]]; then
  echo "error: service-name must be lowercase letters, numbers, or dashes" >&2
  exit 1
fi

if [[ ! "${SERVICE_DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "error: domain must contain only letters, numbers, dots, and dashes" >&2
  exit 1
fi

if [[ ! "${SERVICE_PORT}" =~ ^[0-9]+$ ]] || (( SERVICE_PORT < 1 || SERVICE_PORT > 65535 )); then
  echo "error: internal-port must be a number between 1 and 65535" >&2
  exit 1
fi

SERVICE_ENV_PREFIX="$(echo "SERVICE_${SERVICE_NAME}" | tr '[:lower:]-' '[:upper:]_')"

COMPOSE_TEMPLATE="${TEMPLATE_DIR}/docker-compose.snippet.yml"
CADDY_TEMPLATE="${TEMPLATE_DIR}/Caddyfile.snippet"
SERVICE_OUTPUT_DIR="${SERVICES_DIR}/${SERVICE_NAME}"
COMPOSE_OUTPUT="${SERVICE_OUTPUT_DIR}/docker-compose.snippet.yml"
CADDY_OUTPUT="${CADDY_SITES_DIR}/${SERVICE_NAME}.caddy"

mkdir -p "${SERVICES_DIR}" "${CADDY_SITES_DIR}"

if [[ -e "${SERVICE_OUTPUT_DIR}" || -e "${CADDY_OUTPUT}" ]]; then
  echo "error: service '${SERVICE_NAME}' already exists. Remove the existing snippets first." >&2
  exit 1
fi

# ensure domains remain unique across generated site snippets for predictable routing
if grep -R --no-messages --include "*.caddy" -F "Domain: ${SERVICE_DOMAIN}" "${CADDY_SITES_DIR}" >/dev/null 2>&1 || \
   grep -R --no-messages --include "docker-compose.snippet.yml" -F "Domain: ${SERVICE_DOMAIN}" "${SERVICES_DIR}" >/dev/null 2>&1; then
  echo "error: domain '${SERVICE_DOMAIN}' is already declared in another service" >&2
  exit 1
fi

# prevent internal port clashes inside the shared backbone network
if grep -R --no-messages --include "docker-compose.snippet.yml" -F "\"${SERVICE_PORT}\"" "${SERVICES_DIR}" >/dev/null 2>&1; then
  echo "error: internal port '${SERVICE_PORT}' is already in use by another service snippet" >&2
  exit 1
fi

mkdir -p "${SERVICE_OUTPUT_DIR}"

replace_tokens() {
  local template_file="$1"
  sed \
    -e "s/__SERVICE_NAME__/${SERVICE_NAME}/g" \
    -e "s/__SERVICE_ENV_PREFIX__/${SERVICE_ENV_PREFIX}/g" \
    -e "s/__SERVICE_INTERNAL_PORT__/${SERVICE_PORT}/g" \
    -e "s/__SERVICE_DOMAIN__/${SERVICE_DOMAIN}/g"
}

replace_tokens "${COMPOSE_TEMPLATE}" >"${COMPOSE_OUTPUT}"
replace_tokens "${CADDY_TEMPLATE}" >"${CADDY_OUTPUT}"

cat <<EOF
Generated snippets for service '${SERVICE_NAME}':
  - Compose: ${COMPOSE_OUTPUT}
  - Caddy:   ${CADDY_OUTPUT}
    - Domain: ${SERVICE_DOMAIN}
    - Internal port: ${SERVICE_PORT}

Next steps:
  1. Append ${COMPOSE_OUTPUT} inside the services block of docker/docker-compose.yml.
  2. Review ${CADDY_OUTPUT}; it will be imported automatically by docker/Caddyfile.
  3. Add these environment keys to your .env:
       ${SERVICE_ENV_PREFIX}_IMAGE=<container image>
       ${SERVICE_ENV_PREFIX}_DOMAIN=${SERVICE_DOMAIN}
       ${SERVICE_ENV_PREFIX}_PORT=${SERVICE_PORT}
  4. Validate configuration: docker compose -f docker/docker-compose.yml config
  5. Deploy: docker compose up -d
EOF
