#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_SCALABLE_DIR="${HOME}/.local/share/icons/hicolor/scalable/apps"
CONFIG_DIR="${HOME}/.config/tomatask"
RELEASE_DIR="${ROOT_DIR}/target/release"
BINARIES=(tomatask tomataskd tomatask-status)

SKIP_BUILD=0
FORCE_BUILD=0
START_AFTER_INSTALL=0
CONFIGURE_WAYBAR=0

for arg in "$@"; do
  case "${arg}" in
    --skip-build)
      SKIP_BUILD=1
      ;;
    --force-build)
      FORCE_BUILD=1
      ;;
    --start)
      START_AFTER_INSTALL=1
      ;;
    --configure-waybar)
      CONFIGURE_WAYBAR=1
      ;;
    -h|--help)
      echo "Usage: ./install.sh [--skip-build] [--force-build] [--start] [--configure-waybar]"
      echo "  --skip-build       Install using existing target/release binaries"
      echo "  --force-build      Always run cargo build --release"
      echo "  --start            Launch Tomatask after install"
      echo "  --configure-waybar Add the custom/tomatask module to ~/.config/waybar/config.jsonc"
      echo "                     (backs up the file first; safe to skip and add it yourself, see README.md)"
      exit 0
      ;;
    *)
      echo "Unknown option: ${arg}"
      echo "Run ./install.sh --help for usage."
      exit 1
      ;;
  esac
done

cd "${ROOT_DIR}"

all_binaries_present() {
  for bin in "${BINARIES[@]}"; do
    [[ -x "${RELEASE_DIR}/${bin}" ]] || return 1
  done
  return 0
}

needs_rebuild() {
  if [[ "${FORCE_BUILD}" -eq 1 ]]; then
    return 0
  fi

  if ! all_binaries_present; then
    return 0
  fi

  local newest_bin
  newest_bin="${RELEASE_DIR}/tomatask"

  if [[ -n "$(find "${ROOT_DIR}/src" -type f -newer "${newest_bin}" -print -quit)" ]]; then
    return 0
  fi

  if [[ "${ROOT_DIR}/Cargo.toml" -nt "${newest_bin}" ]]; then
    return 0
  fi

  if [[ -f "${ROOT_DIR}/Cargo.lock" && "${ROOT_DIR}/Cargo.lock" -nt "${newest_bin}" ]]; then
    return 0
  fi

  return 1
}

if [[ "${SKIP_BUILD}" -eq 1 ]]; then
  if ! all_binaries_present; then
    echo "--skip-build requested, but one or more release binaries are missing in ${RELEASE_DIR}."
    echo "Run without --skip-build to build them first."
    exit 1
  fi
  echo "Skipping build and using existing release binaries."
elif needs_rebuild; then
  echo "Building release binaries..."
  if rustup show active-toolchain 2>/dev/null | rg -q '^no active toolchain'; then
    cargo +stable build --release
  else
    cargo build --release
  fi
else
  echo "Using existing release binaries (already up to date)."
fi

mkdir -p "${BIN_DIR}" "${APP_DIR}" "${ICON_SCALABLE_DIR}" "${CONFIG_DIR}"

for bin in "${BINARIES[@]}"; do
  # Copy to a temp file then rename into place. A plain `cp` onto a binary
  # that is currently running (e.g. tomataskd) fails with "Text file busy";
  # renaming replaces the directory entry instead of writing through it, so
  # it works even while the old binary is running.
  tmp_bin="${BIN_DIR}/.${bin}.new"
  cp "${RELEASE_DIR}/${bin}" "${tmp_bin}"
  chmod +x "${tmp_bin}"
  mv -f "${tmp_bin}" "${BIN_DIR}/${bin}"
done

cp "${ROOT_DIR}/config/tomatask.desktop" "${APP_DIR}/tomatask.desktop"

if [[ -f "${ROOT_DIR}/assets/icon-tray.svg" ]]; then
  cp "${ROOT_DIR}/assets/icon-tray.svg" "${ICON_SCALABLE_DIR}/tomatask.svg"
fi

if [[ ! -f "${CONFIG_DIR}/state.toml" ]]; then
  cp "${ROOT_DIR}/config/default-state.toml" "${CONFIG_DIR}/state.toml"
fi

echo "Tomatask installed."
echo "Run: ${BIN_DIR}/tomatask"
echo
echo "Background timer + tasks are owned by tomataskd, which auto-starts the"
echo "first time you run tomatask or tomatask-status (e.g. from a Waybar module)."

if [[ "${CONFIGURE_WAYBAR}" -eq 1 ]]; then
  echo
  "${ROOT_DIR}/scripts/configure-waybar.sh"
else
  echo "Waybar was left untouched. Re-run with --configure-waybar to add the"
  echo "custom/tomatask module automatically, or see README.md to add it yourself."
fi

if [[ "${START_AFTER_INSTALL}" -eq 1 ]]; then
  nohup "${BIN_DIR}/tomatask" >/tmp/tomatask.log 2>&1 &
  echo "Tomatask started in background (log: /tmp/tomatask.log)."
fi
