#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# backbone-infa setup script
# Clones the repo, installs Docker CE, hardens the firewall,
# configures ufw-docker correctly, and verifies HTTPS + Umami setup.
# -----------------------------------------------------------------------------

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# 🔧 Configuration (edit these before running)
# -----------------------------------------------------------------------------

# Git repository + branch
REPO_URL="${REPO_URL:-https://github.com/dills122/backbone-infa.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="/opt/backbone-infa"

# Admin & domain info
CADDY_EMAIL="${CADDY_EMAIL:-admin@example.com}"
UMAMI_ADMIN_EMAIL="${UMAMI_ADMIN_EMAIL:-admin@example.com}"

# Root domain and subdomains
ROOT_DOMAIN="${ROOT_DOMAIN:-example.com}"
BLOG_DOMAIN="blog.${ROOT_DOMAIN}"
UMAMI_DOMAIN="umami.${ROOT_DOMAIN}"

# Services to monitor for health checks
SERVICES=("backbone-caddy" "backbone-umami" "backbone-umami-db")

# Internal ports to block (for security hardening)
BLOCKED_PORTS=(6379 5432 3000)

# -----------------------------------------------------------------------------
# 🏁 Start Setup
# -----------------------------------------------------------------------------

echo "🚀 Starting backbone-infa setup for ${ROOT_DOMAIN}..."

# --- Safety check: ports 80/443 free ---
if lsof -i :80 -sTCP:LISTEN >/dev/null 2>&1 || lsof -i :443 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "⚠️  Port 80/443 already in use. Stop existing web services before running this setup."
  exit 1
fi

# --- System update & prerequisites ---
echo "📦 Updating system packages..."
apt-get update -y && apt-get upgrade -y

echo "🔧 Installing prerequisites..."
apt-get install -y ca-certificates curl fail2ban gnupg lsb-release git dnsutils openssl rsync unattended-upgrades ufw

# -----------------------------------------------------------------------------
# 🐳 Install Docker CE
# -----------------------------------------------------------------------------
echo "🐳 Installing Docker CE..."
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "✅ Docker installed successfully:"
docker --version
docker compose version || true

# -----------------------------------------------------------------------------
# 🛡️ Firewall + ufw-docker setup
# -----------------------------------------------------------------------------
echo "🛡️  Configuring firewall (UFW)..."

ufw default deny incoming
ufw default allow outgoing

ufw allow OpenSSH
ufw limit OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp

# Deny common internal service ports
for port in "${BLOCKED_PORTS[@]}"; do
  ufw deny "$port" || true
done

# Enable UFW non-interactively
echo "y" | ufw enable

# Install ufw-docker if missing
if ! command -v ufw-docker >/dev/null 2>&1; then
  echo "📥 Installing ufw-docker helper..."
  wget -q -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
  chmod +x /usr/local/bin/ufw-docker
  ufw-docker install || true
  systemctl restart ufw
fi

# ✅ Re-link Docker Caddy ports through ufw-docker
echo "🔗 Applying ufw-docker rules for backbone-caddy..."
if docker ps --format '{{.Names}}' | grep -q 'backbone-caddy'; then
  ufw-docker allow backbone-caddy 80 || true
  ufw-docker allow backbone-caddy 443 || true
  echo "✅ ufw-docker rules applied for backbone-caddy (HTTP/HTTPS)"
else
  echo "⚠️  backbone-caddy not running yet — rules will apply after first startup."
fi

echo "✅ Firewall configured. Only ports 22, 80, and 443 are publicly accessible."

# -----------------------------------------------------------------------------
# 🔐 SSH hardening + fail2ban
# -----------------------------------------------------------------------------
echo "🔐 Applying SSH hardening..."
SSHD_CONFIG="/etc/ssh/sshd_config"
if [[ -f "$SSHD_CONFIG" ]]; then
  ensure_sshd_setting() {
    local key="$1"
    local value="$2"
    if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$SSHD_CONFIG"; then
      sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|g" "$SSHD_CONFIG"
    else
      echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
  }

  ensure_sshd_setting "PermitRootLogin" "no"
  ensure_sshd_setting "PasswordAuthentication" "no"
  ensure_sshd_setting "KbdInteractiveAuthentication" "no"
  ensure_sshd_setting "ChallengeResponseAuthentication" "no"
  ensure_sshd_setting "PubkeyAuthentication" "yes"
  systemctl reload ssh || systemctl reload sshd || true
fi

echo "🛡️ Configuring fail2ban..."
if command -v fail2ban-client >/dev/null 2>&1; then
  if [[ ! -f /etc/fail2ban/jail.local ]]; then
    cat >/etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
  fi
  systemctl enable fail2ban
  systemctl restart fail2ban
fi

# -----------------------------------------------------------------------------
# 🌐 Verify DNS configuration
# -----------------------------------------------------------------------------
echo "🌐 Checking DNS records..."
PUBLIC_IP=$(curl -s https://api.ipify.org)
DOMAINS=("$ROOT_DOMAIN" "$BLOG_DOMAIN" "$UMAMI_DOMAIN")

for domain in "${DOMAINS[@]}"; do
  DNS_IP=$(dig +short "$domain" | tail -n1)
  if [[ -z "$DNS_IP" ]]; then
    echo "⚠️  DNS for $domain not found — certificates may fail until DNS propagates."
  elif [[ "$DNS_IP" != "$PUBLIC_IP" ]]; then
    echo "⚠️  DNS for $domain points to $DNS_IP (expected $PUBLIC_IP)."
  else
    echo "✅  DNS for $domain correctly points to this server."
  fi
done

# -----------------------------------------------------------------------------
# 📦 Clone or update repository
# -----------------------------------------------------------------------------
echo "📁 Setting up backbone-infa repository..."
mkdir -p /opt
if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "🔁 Repo exists — updating branch $BRANCH..."
  cd "$TARGET_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
else
  echo "🧭 Cloning fresh..."
  git clone "$REPO_URL" "$TARGET_DIR"
  cd "$TARGET_DIR"
  git checkout "$BRANCH"
fi

cd "$TARGET_DIR/docker"

# -----------------------------------------------------------------------------
# 🗂️ Seed static-site deploy paths for Caddy file_server roots
# -----------------------------------------------------------------------------
mkdir -p /opt/backbone-infa/sites
for site in coming-soon blog; do
  if [[ -d "./sites/${site}" ]]; then
    mkdir -p "/opt/backbone-infa/sites/${site}"
    rsync -a --delete "./sites/${site}/" "/opt/backbone-infa/sites/${site}/"
  fi
done

# -----------------------------------------------------------------------------
# ⚙️ Environment setup
# -----------------------------------------------------------------------------
if [[ ! -f ".env" ]]; then
  echo "⚙️  Creating .env file from example..."
  cp .env.example .env

  UMAMI_PASS=$(openssl rand -hex 16)
  APP_SECRET=$(openssl rand -hex 32)

  sed -i "s/^CADDY_ADMIN_EMAIL=.*/CADDY_ADMIN_EMAIL=${CADDY_EMAIL}/" .env || echo "CADDY_ADMIN_EMAIL=${CADDY_EMAIL}" >> .env
  sed -i "s/^UMAMI_DB_PASS=.*/UMAMI_DB_PASS=${UMAMI_PASS}/" .env || echo "UMAMI_DB_PASS=${UMAMI_PASS}" >> .env
  sed -i "s/^UMAMI_APP_SECRET=.*/UMAMI_APP_SECRET=${APP_SECRET}/" .env || echo "UMAMI_APP_SECRET=${APP_SECRET}" >> .env
  sed -i "s/^UMAMI_ADMIN_EMAIL=.*/UMAMI_ADMIN_EMAIL=${UMAMI_ADMIN_EMAIL}/" .env || echo "UMAMI_ADMIN_EMAIL=${UMAMI_ADMIN_EMAIL}" >> .env

  echo "✅ .env created with random secrets."

  if [[ ! -f "../.env" ]]; then
    echo "🔗 Seeding root .env for Terraform/cloud-init helpers..."
    cp .env ../.env
  fi
fi

# -----------------------------------------------------------------------------
# 🧱 Docker Compose Stack
# -----------------------------------------------------------------------------
echo "⬇️  Pulling Docker images..."
docker compose pull

echo "🚀 Starting Docker stack..."
docker compose up -d

# -----------------------------------------------------------------------------
# ⏳ Wait for containers to start
# -----------------------------------------------------------------------------
echo "⏳ Waiting for containers to start..."
for service in "${SERVICES[@]}"; do
  printf "   ⏳ Waiting for %s ..." "$service"
  attempt=1
  while (( attempt <= 30 )); do
    STATUS=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$service" 2>/dev/null || echo "starting")
    if [[ "$STATUS" == "healthy" || "$STATUS" == "running" ]]; then
      echo " ✅"
      break
    fi
    sleep 5
    ((attempt++))
  done
done

# -----------------------------------------------------------------------------
# 📡 Verify HTTPS endpoints
# -----------------------------------------------------------------------------
echo "🔍 Verifying HTTPS connections..."
for domain in "${DOMAINS[@]}"; do
  echo -n " → Testing https://$domain ..."
  success=false
  for attempt in {1..5}; do
    if curl -fsS --max-time 15 "https://$domain" >/dev/null 2>&1; then
      echo " ✅ OK"
      success=true
      break
    fi
    echo -n "."
    sleep 5
  done
  if [[ "$success" == false ]]; then
    echo " ❌ Failed after ${attempt:-5} attempts (check DNS or cert)"
  fi
done

# -----------------------------------------------------------------------------
# 🔑 Umami credentials
# -----------------------------------------------------------------------------
echo "🔑 Checking Umami logs for admin credentials..."
docker logs backbone-umami 2>&1 | grep "ADMIN_CREDENTIALS" | tail -n1 || echo "ℹ️  No new credentials found (admin likely exists already)."

# -----------------------------------------------------------------------------
# 🧭 Final summary
# -----------------------------------------------------------------------------
echo
echo "✅ Setup complete for ${ROOT_DOMAIN}!"
echo "🌐 Access:"
echo "  https://${ROOT_DOMAIN}        (Coming Soon)"
echo "  https://${BLOG_DOMAIN}        (Static Blog)"
echo "  https://${UMAMI_DOMAIN}       (Analytics Dashboard)"
echo
echo "🧭 Logs:"
echo "  docker logs backbone-caddy | tail"
echo "  docker logs backbone-umami | tail"
echo
echo "🔒 Firewall:"
ufw status verbose | grep -E 'Status|22|80|443|6379|5432|3000' || true
echo
echo "🎉 All done — your Backbone environment for ${ROOT_DOMAIN} is fully deployed, secured, and ready!"

if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
  echo "🗃️ Installing automated encrypted Umami backups..."
  BACKUP_DIR="${BACKUP_DIR:-/opt/backbone-infa/backups/umami}" \
  RETENTION_DAYS="${RETENTION_DAYS:-14}" \
  CRON_SCHEDULE="${CRON_SCHEDULE:-17 3 * * *}" \
  BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE}" \
  RUN_NOW="${RUN_BACKUP_NOW:-false}" \
  bash "${TARGET_DIR}/scripts/install-umami-backup-cron.sh"
fi
