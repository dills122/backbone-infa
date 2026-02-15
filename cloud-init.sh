#!/usr/bin/env bash
# Updated: Idempotent bootstrap for Docker host provisioning with Git repo sync and Caddy prerequisites.

set -euo pipefail

LOG_PATH="/var/log/backbone-bootstrap.log"
STATE_DIR="/var/lib/backbone"
PRIMARY_USER="ubuntu"
PRIMARY_GROUP="$PRIMARY_USER"
# shellcheck disable=SC2154
SSH_AUTHORIZED_KEY="${ssh_public_key}"
# shellcheck disable=SC2154
REPO_URL="${repo_url}"
# shellcheck disable=SC2154
TIMEZONE="${timezone}"
# shellcheck disable=SC2154
CADDY_EMAIL="${caddy_email}"
REPO_DIR="/opt/backbone-infa"
SYSTEMD_DOCKER_UNIT="docker"
COMPOSE_FILE="$REPO_DIR/docker/docker-compose.yml"
ENV_FILE="$REPO_DIR/docker/.env"

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
      fail2ban \
      git \
      gnupg \
      lsb-release \
      rsync \
      unattended-upgrades \
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
  # shellcheck source=/dev/null
  cat <<EOF >/etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && printf '%s' "$VERSION_CODENAME") stable
EOF
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
    ufw --force default deny incoming
    ufw --force default allow outgoing
    ufw --force allow OpenSSH
    ufw --force limit OpenSSH
    ufw --force allow 80/tcp
    ufw --force allow 443/tcp
    if ! ufw status | grep -q "Status: active"; then
      info "Enabling UFW firewall with SSH/HTTP/HTTPS"
      ufw --force enable
    fi
  fi
}

ensure_ssh_hardening() {
  local sshd_config="/etc/ssh/sshd_config"

  if [ ! -f "$sshd_config" ]; then
    return
  fi

  ensure_sshd_setting() {
    local key="$1"
    local value="$2"
    if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$sshd_config"; then
      sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|g" "$sshd_config"
    else
      printf '%s %s\n' "$key" "$value" >>"$sshd_config"
    fi
  }

  info "Applying SSH hardening settings"
  ensure_sshd_setting "PermitRootLogin" "no"
  ensure_sshd_setting "PasswordAuthentication" "no"
  ensure_sshd_setting "KbdInteractiveAuthentication" "no"
  ensure_sshd_setting "ChallengeResponseAuthentication" "no"
  ensure_sshd_setting "PubkeyAuthentication" "yes"

  systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 || true
}

ensure_fail2ban() {
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    return
  fi

  local jail_local="/etc/fail2ban/jail.local"
  if [ ! -f "$jail_local" ]; then
    cat >"$jail_local" <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
  fi

  systemctl enable fail2ban >/dev/null 2>&1 || true
  systemctl restart fail2ban >/dev/null 2>&1 || true
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
    local legacy_env="$REPO_DIR/.env"
    if [ -f "$legacy_env" ]; then
      info "Migrating legacy env file from $legacy_env to $ENV_FILE"
      cp "$legacy_env" "$ENV_FILE"
      chown "$PRIMARY_USER:$PRIMARY_GROUP" "$ENV_FILE" || true
    else
      info "Environment file $ENV_FILE not present; skipping stack start"
      return
    fi
  fi

  info "Starting docker stack via compose"
  compose up -d
}

prepare_static_sites() {
  local static_src="$REPO_DIR/docker/sites"
  local static_dst="/opt/backbone-infa/sites"

  if [ ! -d "$static_src" ]; then
    return
  fi

  mkdir -p "$static_dst"

  for site in blog coming-soon; do
    if [ -d "$static_src/$site" ]; then
      info "Seeding static site content for $site"
      mkdir -p "$static_dst/$site"
      rsync -a --delete "$static_src/$site/" "$static_dst/$site/"
    fi
  done
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
  ensure_ssh_hardening
  ensure_fail2ban
  ensure_timezone
  ensure_user
  ensure_repo
  prepare_static_sites
  write_caddy_email_hint
  run_compose
  verify_compose_stack
  info "Backbone bootstrap complete"
}

main "$@"
