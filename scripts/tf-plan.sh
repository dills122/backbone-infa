#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Terraform plan/apply helper
# Loads .env, exports TF_VAR_* environment variables, and runs Terraform.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- CONFIG ---
TERRAFORM_DIR="terraform"
ENV_FILE=".env"

# --- CHECK ENV FILE ---
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Error: $ENV_FILE not found in $(pwd)"
  echo "Please create it with DO_TOKEN (and optional SSH/DNS overrides)."
  exit 1
fi

# --- LOAD ENV FILE SAFELY ---
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# --- EXPORT TERRAFORM VARIABLES ---
if [[ -z "${DO_TOKEN:-}" ]]; then
  echo "❌ DO_TOKEN not set in $ENV_FILE"
  exit 1
fi

export TF_VAR_do_token="$DO_TOKEN"

# Optional: use an existing uploaded DigitalOcean SSH key fingerprint.
if [[ -n "${SSH_KEY_FINGERPRINT:-}" ]]; then
  normalized_fingerprint="$SSH_KEY_FINGERPRINT"
  if [[ "$normalized_fingerprint" =~ MD5:([0-9a-fA-F:]{47}) ]]; then
    normalized_fingerprint="${BASH_REMATCH[1]}"
  fi
  if [[ "$normalized_fingerprint" =~ ^[0-9a-fA-F:]{47}$ ]]; then
    normalized_fingerprint="$(printf '%s' "$normalized_fingerprint" | tr '[:upper:]' '[:lower:]')"
    export TF_VAR_ssh_key_fingerprint="$normalized_fingerprint"
  else
    echo "❌ SSH_KEY_FINGERPRINT format invalid. Expected aa:bb:... (32 hex bytes, colon-separated)."
    exit 1
  fi
fi

# Optional overrides if you don't want default ~/.ssh/id_ed25519.pub behavior.
if [[ -n "${SSH_PUBLIC_KEY_PATH:-}" ]]; then
  export TF_VAR_ssh_public_key_path="$SSH_PUBLIC_KEY_PATH"
fi

if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
  export TF_VAR_ssh_public_key="$SSH_PUBLIC_KEY"
fi

# Optional DNS management variables (explicit opt-in only).
if [[ "${ENABLE_TERRAFORM_DNS_AUTOMATION:-false}" == "true" ]]; then
  if [[ -n "${DOMAIN_NAME:-}" ]]; then
    export TF_VAR_domain_name="$DOMAIN_NAME"
  fi

  if [[ -n "${MANAGE_DNS_RECORDS:-}" ]]; then
    export TF_VAR_manage_dns_records="$MANAGE_DNS_RECORDS"
  fi

  if [[ -n "${DNS_TTL:-}" ]]; then
    export TF_VAR_dns_ttl="$DNS_TTL"
  fi

  if [[ -n "${ROOT_RECORD_NAME:-}" ]]; then
    export TF_VAR_root_record_name="$ROOT_RECORD_NAME"
  fi

  if [[ -n "${BLOG_RECORD_NAME:-}" ]]; then
    export TF_VAR_blog_record_name="$BLOG_RECORD_NAME"
  fi

  if [[ -n "${UMAMI_RECORD_NAME:-}" ]]; then
    export TF_VAR_umami_record_name="$UMAMI_RECORD_NAME"
  fi

  if [[ -n "${WWW_RECORD_NAME:-}" ]]; then
    export TF_VAR_www_record_name="$WWW_RECORD_NAME"
  fi
fi

# --- TERRAFORM COMMAND HANDLER ---
ACTION=${1:-plan}
PLAN_FILE="backbone.tfplan"

echo "🚀 Running Terraform (${ACTION}) in $TERRAFORM_DIR ..."
cd "$TERRAFORM_DIR"

terraform init -input=false

case "$ACTION" in
  plan)
    terraform plan -out "$PLAN_FILE"
    ;;
  apply)
    terraform apply "$PLAN_FILE"
    ;;
  destroy)
    terraform destroy
    ;;
  *)
    echo "Usage: $0 [plan|apply|destroy]"
    exit 1
    ;;
esac

echo "✅ Terraform $ACTION completed successfully."
