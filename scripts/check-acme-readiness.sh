#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-acme-readiness.sh <base-domain> <expected-ip> [--restart-caddy]

Examples:
  scripts/check-acme-readiness.sh dsteele.dev 45.55.234.244
  scripts/check-acme-readiness.sh dsteele.dev 45.55.234.244 --restart-caddy

Notes:
  - This verifies DNS delegation and authoritative A records for:
      @, www, blog, umami
  - If --restart-caddy is passed and all checks are green, it restarts caddy
    using:
      /opt/backbone-infa/docker/docker-compose.yml
      /opt/backbone-infa/docker/.env
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

BASE_DOMAIN="$1"
EXPECTED_IP="$2"
RESTART_CADDY="${3:-}"

if [[ -n "$RESTART_CADDY" && "$RESTART_CADDY" != "--restart-caddy" ]]; then
  echo "❌ Unknown flag: $RESTART_CADDY" >&2
  usage
  exit 1
fi

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Missing dependency: $cmd" >&2
    exit 1
  fi
}

require_command dig
require_command awk
require_command grep
require_command sort
require_command tr
require_command sed

hosts=("@" "www" "blog" "umami")
auth_ns=("ns1.digitalocean.com" "ns2.digitalocean.com" "ns3.digitalocean.com")
all_ok=true

to_fqdn() {
  local name="$1"
  if [[ "$name" == "@" ]]; then
    printf '%s\n' "$BASE_DOMAIN"
  else
    printf '%s.%s\n' "$name" "$BASE_DOMAIN"
  fi
}

unique_one_line() {
  local text="${1:-}"
  if [[ -z "$text" ]]; then
    printf '(none)\n'
    return
  fi
  printf '%s\n' "$text" | awk 'NF' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]\+$//'
  printf '\n'
}

contains_expected() {
  local ips_text="${1:-}"
  if printf '%s\n' "$ips_text" | grep -Fxq "$EXPECTED_IP"; then
    return 0
  fi
  return 1
}

echo "🔎 ACME readiness check for: $BASE_DOMAIN"
echo "🎯 Expected A record target: $EXPECTED_IP"
echo

echo "1) Parent delegation check (gTLD)"
parent_ok=true
for parent_ns in a.gtld-servers.net b.gtld-servers.net; do
  echo "   @$parent_ns"
  delegation="$(
    dig +norecurse +noall +authority @"$parent_ns" "$BASE_DOMAIN" NS \
      | awk '$4=="NS" {print $5}' \
      | sed 's/\.$//' \
      | awk 'NF'
  )"
  if [[ -z "$delegation" ]]; then
    echo "      (no delegation in authority section)"
    parent_ok=false
  else
    printf '      %s\n' "$delegation"
  fi
done
if [[ "$parent_ok" == "false" ]]; then
  echo "   ⚠️  Parent delegation check inconclusive from this host (continuing)."
fi
echo

echo "2) Authoritative A record check"
for host in "${hosts[@]}"; do
  fqdn="$(to_fqdn "$host")"
  echo "   $fqdn"
  for ns in "${auth_ns[@]}"; do
    ips="$(dig +norecurse +short @"$ns" "$fqdn" A | awk 'NF')"
    joined="$(unique_one_line "$ips")"
    printf '    @%-30s -> %s\n' "$ns" "$joined"
    if contains_expected "$ips"; then
      echo "      ✅ contains $EXPECTED_IP"
    else
      echo "      ❌ missing $EXPECTED_IP"
      all_ok=false
    fi
  done
done
echo

echo "3) SOA serial check (authoritative sync)"
soa_serials=""
for ns in "${auth_ns[@]}"; do
  serial="$(dig +norecurse +short @"$ns" "$BASE_DOMAIN" SOA | awk '{print $3}')"
  if [[ -z "$serial" ]]; then
    serial="(none)"
    all_ok=false
  fi
  printf '   @%-30s -> %s\n' "$ns" "$serial"
  soa_serials="${soa_serials}${serial}"$'\n'
done

unique_serial_count="$(printf '%s\n' "$soa_serials" | awk 'NF' | sort -u | wc -l | tr -d ' ')"
if [[ "$unique_serial_count" != "1" ]]; then
  echo "   ❌ SOA serial mismatch across authoritative nameservers"
  all_ok=false
else
  echo "   ✅ SOA serials match"
fi
echo

if [[ "$all_ok" == "true" ]]; then
  echo "✅ DNS is converged for ACME validation."
  if [[ "$RESTART_CADDY" == "--restart-caddy" ]]; then
    compose_file="/opt/backbone-infa/docker/docker-compose.yml"
    env_file="/opt/backbone-infa/docker/.env"

    if command -v docker >/dev/null 2>&1 && [[ -f "$compose_file" && -f "$env_file" ]]; then
      echo "🔄 Restarting caddy container..."
      docker compose -f "$compose_file" --env-file "$env_file" restart caddy
      echo "📜 Recent caddy logs:"
      docker compose -f "$compose_file" --env-file "$env_file" logs --tail=80 caddy
    else
      echo "⚠️  Skipping restart: docker/compose file/env not available on this machine."
    fi
  else
    echo "ℹ️  Next step: restart caddy on the droplet to trigger cert obtain."
  fi
else
  echo "❌ DNS is not fully converged yet. Do not restart caddy for cert issuance yet."
  exit 2
fi
