#!/usr/bin/env bash
set -euo pipefail

echo "== Tomatask Doctor =="

echo "[1] Binaries:"
for bin in tomatask tomataskd tomatask-status; do
  path="$(command -v "${bin}" 2>/dev/null || true)"
  if [[ -n "${path}" ]]; then
    echo "  ${bin}: ${path}"
  else
    echo "  ${bin}: NOT FOUND on PATH (expected in ~/.local/bin)"
  fi
done

echo
echo "[2] Daemon process:"
pgrep -a tomataskd || echo "  tomataskd is not running (it auto-starts on first tomatask/tomatask-status run)"

echo
echo "[3] Daemon socket:"
SOCKET="${XDG_RUNTIME_DIR:-/tmp}/tomatask.sock"
if [[ -S "${SOCKET}" ]]; then
  echo "  Found: ${SOCKET}"
else
  echo "  Not found: ${SOCKET}"
fi

echo
echo "[4] Waybar status output (tomatask-status):"
if command -v tomatask-status >/dev/null 2>&1; then
  tomatask-status
else
  echo "  tomatask-status not installed"
fi

echo
echo "[5] Persisted state file:"
STATE_FILE="${HOME}/.config/tomatask/state.toml"
if [[ -f "${STATE_FILE}" ]]; then
  echo "  Found: ${STATE_FILE}"
else
  echo "  Not found: ${STATE_FILE}"
fi

echo
echo "[6] Theme source:"
if [[ -f "${HOME}/.config/tomatask/theme.toml" ]]; then
  echo "  Using override: ~/.config/tomatask/theme.toml"
elif [[ -f "${HOME}/.config/omarchy/current/theme/colors.toml" ]]; then
  echo "  Using Omarchy theme: ~/.config/omarchy/current/theme/colors.toml"
else
  echo "  No theme file found, using built-in defaults"
fi
