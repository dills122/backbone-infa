#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# backbone-infa setup script
# Clones the repo, checks out big-refactor, installs Docker CE,
# bootstraps the environment, and verifies HTTPS + Umami setup.
# -----------------------------------------------------------------------------

set -euo pipefail

REPO_URL="https://github.com/dills122/backbone-infa.git"
TARGET_DIR="/opt/backbone-infa"
BRANCH="big-refactor"
CADDY_EMAIL="dylansteele57@gmail.com"

echo "🚀 Starting backbone-infa setup..."

# --- Safety checks ---
if lsof -i :80 -sTCP:LISTEN >/dev/null 2>&1 || lsof -i :443 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "⚠️  Port 80/443 already in use. Stop existing web services before running this setup."
  exit 1
fi

# --- System setup ---
echo "📦 Updating system packages..."
apt-get update -y && apt-get upgrade -y

echo "🔧 Installing prerequisites..."
apt-get install -y ca-certificates curl gnupg lsb-release git

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

# --- Repo setup ---
echo "📁 Cloning or updating repository..."
mkdir -p /opt
if [[ -d "$TARGET_DIR/.git" ]]; then
  cd "$TARGET_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
else
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
  echo "UMAMI_APP_SECRET=${APP_SECRET}" >> .env

  echo "✅ .env created with random secrets."
fi

# --- Pull and start containers ---
echo "⬇️  Pulling Docker images..."
docker compose pull

echo "🚀 Starting Docker stack..."
docker compose up -d

# --- Wait for Caddy & Umami to come up ---
echo "⏳ Waiting for containers to start..."
sleep 15

echo "📡 Checking running containers..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# --- Validate HTTPS endpoints ---
echo "🔍 Verifying HTTPS connections..."
for domain in dsteele.dev blog.dsteele.dev umami.dsteele.dev; do
  echo -n " → Testing https://$domain ... "
  if curl -fsS --max-time 20 "https://$domain" >/dev/null 2>&1; then
    echo "✅ OK"
  else
    echo "❌ Failed (check DNS or cert)"
  fi
done

# --- Umami credential extraction ---
echo "🔑 Checking Umami logs for admin credentials..."
docker logs backbone-umami 2>&1 | grep "ADMIN_CREDENTIALS" | tail -n1 || echo "ℹ️  No new credentials found (admin likely exists already)."

# --- Summary ---
echo
echo "✅ Setup complete!"
echo "🌐 Access:"
echo "  https://dsteele.dev           (Coming Soon)"
echo "  https://blog.dsteele.dev      (Static Blog)"
echo "  https://umami.dsteele.dev     (Analytics)"
echo
echo "🧭 To inspect logs:"
echo "  docker logs backbone-caddy | tail"
echo "  docker logs backbone-umami | tail"
echo
echo "🎉 All done!"
