#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ docker is required for compose validation." >&2
  exit 1
fi

echo "🔎 Validating Docker Compose config..."
docker compose -f docker/docker-compose.yml --env-file docker/.env.example config >/dev/null
echo "✅ Docker Compose config is valid."
