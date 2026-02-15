#!/usr/bin/env bash
set -euo pipefail

if ! command -v terraform >/dev/null 2>&1; then
  echo "❌ terraform is required for validation." >&2
  exit 1
fi

echo "🔎 Running terraform fmt check..."
terraform -chdir=terraform fmt -check -recursive

echo "🔎 Running terraform init (backend disabled)..."
terraform -chdir=terraform init -backend=false -input=false >/dev/null

echo "🔎 Running terraform validate..."
terraform -chdir=terraform validate

echo "✅ Terraform validation passed."
