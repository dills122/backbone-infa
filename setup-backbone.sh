#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# backbone-infa setup script
# Clones the repo, installs Docker CE, hardens the firewall,
# verifies HTTPS + Umami setup, and configures a full production-ready stack.
# -----------------------------------------------------------------------------

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# 🔧 Configuration (edit these before running)
# -----------------------------------------------------------------------------

# Git repository + branch
REPO_URL="https://github.com/dills122/backbone-infa.git"
BRANCH="big-refactor"
TARGET_DIR="/opt/backbone-infa"

# Admin & domain info
CADDY_EMAIL="dylansteele57@gmail.com"
UMAMI_ADMIN_EMAIL="admin@local.dev"

# Root domain and subdomains
ROOT_DOMAIN="dsteele.dev"
BLOG_DOMAIN="blog.${ROOT_DOMAIN}"
UMAMI_DOMAIN="umami.${ROOT_DOMAIN}"

# Services you expect to start (used for health checks)
SERVICES=("backbone-caddy" "backbone-umami" "backbone-blog" "backbone-coming-soon")

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

# --- Update & prerequisites ---
echo "📦 Updating system packages..."
apt-get update -y && apt-get upgrade -y

echo "🔧 Installing prerequisites..."
apt-get install -y ca-certificates curl gnupg lsb-release git dnsutils openssl ufw

# --- Install Docker CE ---
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

# --- Setup firewall (UFW) ---
echo "🛡️  Configuring firewall (UFW)..."
ufw default deny incoming
ufw default allow outgoing

ufw allow OpenSSH
ufw allow 'Nginx Full'  # Ports 80 + 443 for Caddy

for port in "${BLOCKED_PORTS[@]}"; do
  ufw deny "$port" || true
done

# Enable UFW non-interactively
echo "y" | ufw enable

# Install ufw-docker if missing
if ! command -v ufw-docker >/dev/null 2>&1; then
  wget -q -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
  chmod +x /usr/local/bin/ufw-docker
  ufw-docker install || true
  systemctl restart ufw
fi

echo "✅ Firewall configured. Only ports 22, 80, and 443 are publicly accessible."

# --- Verify DNS configuration before TLS setup ---
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

# --- Clone or update repo ---
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

# --- Env setup ---
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
fi

# --- Pull and start containers ---
echo "⬇️  Pulling Docker images..."
docker compose pull

echo "🚀 Starting Docker stack..."
docker compose up -d

# --- Wait for containers to become healthy ---
echo "⏳ Waiting for containers to start..."
for service in "${SERVICES[@]}"; do
  printf "   ⏳ Waiting for %s ..." "$service"
  for i in {1..30}; do
    STATUS=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$service" 2>/dev/null || echo "starting")
    if [[ "$STATUS" == "healthy" || "$STATUS" == "running" ]]; then
      echo " ✅"
      break
    fi
    sleep 5
  done
done

# --- Check running containers ---
echo "📡 Current container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# --- Verify HTTPS endpoints with retries ---
echo "🔍 Verifying HTTPS connections..."
for domain in "${DOMAINS[@]}"; do
  echo -n " → Testing https://$domain ..."
  success=false
  # shellcheck disable=SC2034
  for i in {1..5}; do
    if curl -fsS --max-time 15 "https://$domain" >/dev/null 2>&1; then
      echo " ✅ OK"
      success=true
      break
    fi
    echo -n "."
    sleep 5
  done
  if [[ "$success" == false ]]; then
    echo " ❌ Failed (check DNS or cert)"
  fi
done

# --- Umami admin credentials ---
echo "🔑 Checking Umami logs for admin credentials..."
docker logs backbone-umami 2>&1 | grep "ADMIN_CREDENTIALS" | tail -n1 || echo "ℹ️  No new credentials found (admin likely exists already)."

# --- Final summary ---
echo
echo "✅ Setup complete!"
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
echo "🎉 All done — your Backbone environment for ${ROOT_DOMAIN} is fully deployed and secured!"
