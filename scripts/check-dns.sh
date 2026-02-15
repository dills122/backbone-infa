#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/check-dns.sh <base-domain> [expected-ip]

Examples:
  scripts/check-dns.sh dsteele.dev
  scripts/check-dns.sh dsteele.dev 134.209.170.98
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
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
require_command sort
require_command tr

BASE_DOMAIN="$1"
EXPECTED_IP="${2:-}"

names=("@" "www" "blog" "umami")
public_resolvers=("1.1.1.1" "8.8.8.8")

to_fqdn() {
  local name="$1"
  if [[ "$name" == "@" ]]; then
    printf '%s\n' "$BASE_DOMAIN"
  else
    printf '%s.%s\n' "$name" "$BASE_DOMAIN"
  fi
}

unique_join() {
  local text="${1:-}"
  if [[ -z "$text" ]]; then
    printf '(none)\n'
    return
  fi
  printf '%s\n' "$text" | awk 'NF' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]\+$//'
  printf '\n'
}

check_expected() {
  local source="$1"
  local fqdn="$2"
  local ips_text="${3:-}"
  if [[ -z "$EXPECTED_IP" ]]; then
    return
  fi

  if printf '%s\n' "$ips_text" | grep -Fxq "$EXPECTED_IP"; then
    printf '    [%s] ✅ %s contains expected IP %s\n' "$source" "$fqdn" "$EXPECTED_IP"
  else
    printf '    [%s] ❌ %s does not contain expected IP %s\n' "$source" "$fqdn" "$EXPECTED_IP"
  fi
}

echo "🔎 DNS check for base domain: $BASE_DOMAIN"
if [[ -n "$EXPECTED_IP" ]]; then
  echo "🎯 Expected IP: $EXPECTED_IP"
fi
echo

echo "1) Authoritative nameservers"
ns_servers="$(dig NS "$BASE_DOMAIN" +short | sed 's/\.$//' | awk 'NF')"
if [[ -z "$ns_servers" ]]; then
  echo "❌ No NS records found for $BASE_DOMAIN"
  exit 1
fi
printf '   %s\n' "$ns_servers"
echo

echo "2) Authoritative answers"
for name in "${names[@]}"; do
  fqdn="$(to_fqdn "$name")"
  echo "   $fqdn"
  while IFS= read -r ns; do
    ips="$(dig +norecurse @"$ns" "$fqdn" A +short | awk 'NF')"
    joined="$(unique_join "$ips")"
    printf '    @%-35s -> %s\n' "$ns" "$joined"
    check_expected "auth:$ns" "$fqdn" "$ips"
  done <<< "$ns_servers"
done
echo

echo "3) Public resolver answers"
for name in "${names[@]}"; do
  fqdn="$(to_fqdn "$name")"
  echo "   $fqdn"
  for resolver in "${public_resolvers[@]}"; do
    ips="$(dig @"$resolver" "$fqdn" A +short | awk 'NF')"
    joined="$(unique_join "$ips")"
    printf '    @%-35s -> %s\n' "$resolver" "$joined"
    check_expected "resolver:$resolver" "$fqdn" "$ips"
  done
done
echo

echo "4) Local resolver answers (this machine)"
for name in "${names[@]}"; do
  fqdn="$(to_fqdn "$name")"
  ips="$(dig "$fqdn" A +short | awk 'NF')"
  joined="$(unique_join "$ips")"
  printf '   %-40s -> %s\n' "$fqdn" "$joined"
  check_expected "local" "$fqdn" "$ips"
done
echo

echo "5) Optional quick connectivity check (TCP 443)"
for name in "${names[@]}"; do
  fqdn="$(to_fqdn "$name")"
  if command -v nc >/dev/null 2>&1; then
    if nc -z -G 2 "$fqdn" 443 >/dev/null 2>&1; then
      printf '   ✅ %s:443 reachable\n' "$fqdn"
    else
      printf '   ❌ %s:443 not reachable\n' "$fqdn"
    fi
  fi
done
