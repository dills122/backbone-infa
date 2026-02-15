#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ docker is required for compose validation." >&2
  exit 1
fi

cleanup() {
  if [[ "${created_temp_env:-false}" == "true" && -f docker/.env ]]; then
    rm -f docker/.env
  fi
}
trap cleanup EXIT

created_temp_env=false
if [[ ! -f docker/.env ]]; then
  if [[ ! -f docker/.env.example ]]; then
    echo "❌ Missing docker/.env.example; cannot create temporary compose env file." >&2
    exit 1
  fi
  cp docker/.env.example docker/.env
  created_temp_env=true
fi

echo "🔎 Validating Docker Compose config..."
docker compose -f docker/docker-compose.yml --env-file docker/.env.example config >/dev/null
echo "✅ Docker Compose config is valid."
