#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "❌ ripgrep (rg) is required for shell file discovery." >&2
  exit 1
fi

shell_files="$(rg --files -g '*.sh' || true)"
if [[ -z "$shell_files" ]]; then
  echo "ℹ️ No shell scripts found."
  exit 0
fi

echo "🔎 Linting shell scripts..."
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  shellcheck $shell_files
  echo "✅ shellcheck passed."
  exit 0
fi

echo "⚠️ shellcheck not found in PATH."
echo "   Install shellcheck or run lint in an environment where it is available."
exit 1
