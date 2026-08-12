#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
DESKTOP_PATH="${HOME}/.local/share/applications/tomatask.desktop"
ICON_SVG_PATH="${HOME}/.local/share/icons/hicolor/scalable/apps/tomatask.svg"

pkill -x tomataskd 2>/dev/null || true

rm -f "${BIN_DIR}/tomatask" "${BIN_DIR}/tomataskd" "${BIN_DIR}/tomatask-status" \
  "${DESKTOP_PATH}" "${ICON_SVG_PATH}"

echo "Tomatask binaries removed and tomataskd stopped."
echo "User data kept at ~/.config/tomatask"
