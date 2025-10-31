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
  echo "Please create it with DO_TOKEN and SSH_KEY_FINGERPRINT values."
  exit 1
fi

# --- LOAD ENV FILE SAFELY ---
export $(grep -v '^#' "$ENV_FILE" | xargs -I{} echo {} | grep '=')

# --- EXPORT TERRAFORM VARIABLES ---
if [[ -z "${DO_TOKEN:-}" ]]; then
  echo "❌ DO_TOKEN not set in $ENV_FILE"
  exit 1
fi

if [[ -z "${SSH_KEY_FINGERPRINT:-}" ]]; then
  echo "❌ SSH_KEY_FINGERPRINT not set in $ENV_FILE"
  exit 1
fi

export TF_VAR_do_token="$DO_TOKEN"
export TF_VAR_ssh_key_fingerprint="$SSH_KEY_FINGERPRINT"

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
