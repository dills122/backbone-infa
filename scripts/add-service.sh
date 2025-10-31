#!/usr/bin/env bash
# Updated: Generates Compose and Caddy snippets for onboarding a new service.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/templates/service-template"
SERVICES_DIR="${REPO_ROOT}/services"

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

SERVICE_ENV_PREFIX="$(echo "SERVICE_${SERVICE_NAME}" | tr '[:lower:]-' '[:upper:]_')"

mkdir -p "${SERVICES_DIR}"
SERVICE_OUTPUT_DIR="${SERVICES_DIR}/${SERVICE_NAME}"
mkdir -p "${SERVICE_OUTPUT_DIR}"

COMPOSE_TEMPLATE="${TEMPLATE_DIR}/docker-compose.snippet.yml"
CADDY_TEMPLATE="${TEMPLATE_DIR}/Caddyfile.snippet"
COMPOSE_OUTPUT="${SERVICE_OUTPUT_DIR}/docker-compose.snippet.yml"
CADDY_OUTPUT="${REPO_ROOT}/docker/sites/${SERVICE_NAME}.caddy"

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

Next steps:
  1. Append ${COMPOSE_OUTPUT} inside the services block of docker/docker-compose.yml.
  2. Ensure ${CADDY_OUTPUT} is tracked and review the generated site definition.
  3. Add these environment keys to your .env:
       ${SERVICE_ENV_PREFIX}_IMAGE=<container image>
       ${SERVICE_ENV_PREFIX}_DOMAIN=${SERVICE_DOMAIN}
       ${SERVICE_ENV_PREFIX}_PORT=${SERVICE_PORT}
  4. Deploy with: docker compose -f docker/docker-compose.yml up -d
EOF
