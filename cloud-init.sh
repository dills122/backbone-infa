#!/usr/bin/env bash
# Updated: Idempotent bootstrap for Docker host provisioning with Git repo sync and Caddy prerequisites.

set -euo pipefail

LOG_PATH="/var/log/backbone-bootstrap.log"
STATE_DIR="/var/lib/backbone"
PRIMARY_USER="ubuntu"
PRIMARY_GROUP="$PRIMARY_USER"
SSH_AUTHORIZED_KEY="${ssh_public_key}"
REPO_URL="${repo_url}"
TIMEZONE="${timezone}"
CADDY_EMAIL="${caddy_email}"
REPO_DIR="/opt/backbone-infa"
SYSTEMD_DOCKER_UNIT="docker"
COMPOSE_FILE="$REPO_DIR/docker/docker-compose.yml"
ENV_FILE="$REPO_DIR/.env"

mkdir -p "$(dirname "$LOG_PATH")"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_PATH") 2>&1

info() {
  echo "[backbone-init] $*"
}

ensure_user() {
  if ! id -u "$PRIMARY_USER" >/dev/null 2>&1; then
    info "Creating user $PRIMARY_USER"
    useradd --create-home --shell /bin/bash --groups sudo "$PRIMARY_USER"
  fi

  usermod -aG docker "$PRIMARY_USER" 2>/dev/null || true

  local ssh_dir="/home/$PRIMARY_USER/.ssh"
  local auth_file="$ssh_dir/authorized_keys"

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  touch "$auth_file"
  chmod 600 "$auth_file"

  if ! grep -Fq "$SSH_AUTHORIZED_KEY" "$auth_file"; then
    info "Adding authorized key for $PRIMARY_USER"
    printf '%s\n' "$SSH_AUTHORIZED_KEY" >>"$auth_file"
  fi

  chown -R "$PRIMARY_USER:$PRIMARY_GROUP" "$ssh_dir"
}

ensure_timezone() {
  if [ -n "$TIMEZONE" ] && command -v timedatectl >/dev/null 2>&1; then
    CURRENT_TZ="$(timedatectl show --property=Timezone --value)"
    if [ "$CURRENT_TZ" != "$TIMEZONE" ]; then
      info "Setting timezone to $TIMEZONE"
      timedatectl set-timezone "$TIMEZONE"
    fi
  fi
}

ensure_packages() {
  if [ ! -f "$STATE_DIR/packages.installed" ]; then
    info "Updating apt cache and installing base packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y \
      ca-certificates \
      curl \
      git \
      gnupg \
      lsb-release \
      ufw
    touch "$STATE_DIR/packages.installed"
  fi
}

ensure_docker_repo() {
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    info "Adding Docker repository"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    info "Configuring Docker apt source"
    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" >/etc/apt/sources.list.d/docker.list
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    info "Installing Docker packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  systemctl enable "$SYSTEMD_DOCKER_UNIT" >/dev/null 2>&1 || true
  systemctl restart "$SYSTEMD_DOCKER_UNIT" >/dev/null 2>&1 || true
}

ensure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    if ! ufw status | grep -q "Status: active"; then
      info "Enabling UFW firewall with SSH/HTTP/HTTPS"
      ufw --force allow OpenSSH
      ufw --force allow 80/tcp
      ufw --force allow 443/tcp
      ufw --force enable
    fi
  fi
}

ensure_repo() {
  if [ ! -d "$REPO_DIR" ]; then
    info "Cloning repo $REPO_URL"
    git clone "$REPO_URL" "$REPO_DIR"
  else
    info "Updating repo in $REPO_DIR"
    git -C "$REPO_DIR" fetch --all --prune
    if git -C "$REPO_DIR" rev-parse --verify main >/dev/null 2>&1; then
      git -C "$REPO_DIR" checkout main
    fi
    git -C "$REPO_DIR" pull --ff-only || true
  fi

  chown -R "$PRIMARY_USER:$PRIMARY_GROUP" "$REPO_DIR" || true
}

compose() {
  # maintain consistent docker compose invocation with repo-specific context
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

run_compose() {
  if [ ! -f "$COMPOSE_FILE" ]; then
    info "Compose file $COMPOSE_FILE not found; skipping stack start"
    return
  fi

  if [ ! -f "$ENV_FILE" ]; then
    info "Environment file $ENV_FILE not present; skipping stack start"
    return
  fi

  info "Starting docker stack via compose"
  compose up -d
}

verify_compose_stack() {
  # surface container health issues early so bootstrap failures are obvious in logs
  if [ ! -f "$COMPOSE_FILE" ] || [ ! -f "$ENV_FILE" ]; then
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    return
  fi

  info "Verifying compose services are running"
  local running_services
  running_services="$(compose ps --status=running --services 2>/dev/null || true)"

  if ! printf '%s\n' "$running_services" | grep -Fxq "caddy"; then
    info "Caddy is not yet running; dumping compose status for troubleshooting"
    compose ps || true
    compose logs --tail=100 caddy || true
  else
    info "Caddy container is running"
  fi

  local exited_services
  exited_services="$(compose ps --status=exited --services 2>/dev/null || true)"
  if [ -n "$exited_services" ]; then
    info "Detected services with exited status: $exited_services"
    for svc in $exited_services; do
      compose logs --tail=100 "$svc" || true
    done
  fi
}

write_caddy_email_hint() {
  local caddy_env="/etc/backbone-caddy.env"
  if [ -n "$CADDY_EMAIL" ]; then
    printf 'CADDY_ADMIN_EMAIL=%s\n' "$CADDY_EMAIL" >"$caddy_env"
  fi
}

main() {
  info "Beginning backbone bootstrap"
  ensure_packages
  ensure_docker_repo
  ensure_docker
  ensure_firewall
  ensure_timezone
  ensure_user
  ensure_repo
  write_caddy_email_hint
  run_compose
  verify_compose_stack
  info "Backbone bootstrap complete"
}

main "$@"
