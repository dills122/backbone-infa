#!/usr/bin/env bash
set -euo pipefail

RG_BIN=""
if command -v rg >/dev/null 2>&1; then
  RG_BIN="rg"
elif command -v node >/dev/null 2>&1; then
  RG_BIN="$(
    node -e "try { const p=require('@vscode/ripgrep').rgPath; if (p) process.stdout.write(p); } catch (_) {}" 2>/dev/null || true
  )"
fi

if [[ -n "$RG_BIN" && -x "$RG_BIN" ]]; then
  shell_files="$("$RG_BIN" --files -g '*.sh' || true)"
else
  echo "⚠️ ripgrep binary not available; falling back to 'find' for shell discovery."
  shell_files="$(find . -type f -name '*.sh' -not -path './.git/*' -not -path './node_modules/*' | sed 's|^\./||' || true)"
fi
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
