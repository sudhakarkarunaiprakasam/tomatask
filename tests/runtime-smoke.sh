#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PLUGIN_ID="sudhakar.tomatask"

if [[ -z ${OMARCHY_PATH:-} || ! -d $OMARCHY_PATH/shell ]]; then
  echo "skipping runtime smoke test (set OMARCHY_PATH to an Omarchy checkout)"
  exit 0
fi

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  echo "skipping runtime smoke test (no Wayland compositor)"
  exit 0
fi

for command in quickshell jq rg; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "skipping runtime smoke test ($command is unavailable)"
    exit 0
  fi
done

tmpdir=$(mktemp -d)
quickshell_pid=""

cleanup() {
  if [[ -n $quickshell_pid ]] && kill -0 "$quickshell_pid" 2>/dev/null; then
    kill "$quickshell_pid" 2>/dev/null || true
    wait "$quickshell_pid" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

test_root="$tmpdir/omarchy"
test_home="$tmpdir/home"
test_state="$test_home/.local/state"
plugin_dir="$test_home/.config/omarchy/plugins/$PLUGIN_ID"
log="$tmpdir/quickshell.log"

mkdir -p "$test_root" "$plugin_dir" "$test_home/.config/omarchy"
cp -a "$OMARCHY_PATH/shell" "$test_root/shell"
ln -s "$OMARCHY_PATH/bin" "$test_root/bin"
ln -s "$OMARCHY_PATH/config" "$test_root/config"

cp "$ROOT/manifest.json" "$ROOT/Service.qml" "$ROOT/TimerModel.js" \
  "$ROOT/BarWidget.qml" "$ROOT/Panel.qml" "$plugin_dir/"

jq -n --arg plugin "$PLUGIN_ID" '{
  version: 1,
  idle: { screensaver: 150, lock: 300 },
  bar: {
    position: "top",
    style: "floating",
    transparent: false,
    centerAnchor: "",
    layout: { left: [], center: [], right: [{ id: $plugin }] }
  },
  plugins: []
}' >"$test_home/.config/omarchy/shell.json"

shell_ipc() {
  HOME="$test_home" \
  XDG_STATE_HOME="$test_state" \
  OMARCHY_PATH="$test_root" \
    "$OMARCHY_PATH/bin/omarchy-shell" "$@"
}

fail_with_log() {
  sed -n '1,260p' "$log" >&2
  echo "runtime smoke test failed: $1" >&2
  exit 1
}

HOME="$test_home" \
XDG_STATE_HOME="$test_state" \
OMARCHY_PATH="$test_root" \
PATH="$test_root/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
quickshell_pid=$!

for _ in {1..100}; do
  if shell_ipc -q shell ping >/dev/null 2>&1; then
    break
  fi
  kill -0 "$quickshell_pid" 2>/dev/null \
    || fail_with_log "shell exited before IPC became available"
  sleep 0.1
done

plugins=""
for _ in {1..120}; do
  plugins=$(shell_ipc shell listPlugins 2>/dev/null || true)
  if jq -e --arg plugin "$PLUGIN_ID" 'any(.[]; .id == $plugin and .enabled == true)' \
      <<<"$plugins" >/dev/null 2>&1; then
    break
  fi
  kill -0 "$quickshell_pid" 2>/dev/null \
    || fail_with_log "shell exited while loading plugin"
  sleep 0.1
done

jq -e --arg plugin "$PLUGIN_ID" 'any(.[]; .id == $plugin and .enabled == true)' \
  <<<"$plugins" >/dev/null \
  || fail_with_log "plugin was not discovered and enabled"

geometry=""
for _ in {1..120}; do
  geometry=$(shell_ipc shell debugBarGeometry 2>/dev/null || true)
  if jq -e --arg plugin "$PLUGIN_ID" 'any(.[]; .id == $plugin and .visible == true and .width > 0 and .height > 0)' \
      <<<"$geometry" >/dev/null 2>&1; then
    break
  fi
  kill -0 "$quickshell_pid" 2>/dev/null \
    || fail_with_log "shell exited before bar widget rendered"
  sleep 0.1
done

jq -e --arg plugin "$PLUGIN_ID" 'any(.[]; .id == $plugin and .visible == true and .width > 0 and .height > 0)' \
  <<<"$geometry" >/dev/null \
  || fail_with_log "bar widget did not render"

[[ $(shell_ipc shell summon "$PLUGIN_ID") == "ok" ]] \
  || fail_with_log "panel could not be summoned"
shell_ipc -q shell hide "$PLUGIN_ID" >/dev/null \
  || fail_with_log "panel could not be hidden"
shell_ipc -q shell toggle "$PLUGIN_ID" >/dev/null \
  || fail_with_log "panel could not be toggled"
shell_ipc -q shell hide "$PLUGIN_ID" >/dev/null \
  || fail_with_log "toggled panel could not be hidden"

state_path="$test_state/omarchy/tomatask.json"
for _ in {1..80}; do
  [[ -s $state_path ]] && break
  sleep 0.1
done

[[ -s $state_path ]] || fail_with_log "state file was not persisted"

jq -e '
  .version == 1 and
  (.timerState.status == "stopped") and
  (.timerState.phase == "work") and
  (.timerState.phaseDurationSec == 1500) and
  (.timerState.remainingSec == 1500) and
  (.activeTaskId | type == "string") and
  (.tasks | type == "array") and
  (.tasks | length >= 1) and
  (.tasks[0].name == "Inbox") and
  (.tasks[0].sessions == 0)
' "$state_path" >/dev/null \
  || fail_with_log "persisted state shape did not match expectations"

if rg -i '(^|[^a-z])(tomatask|sudhakar\.tomatask).*(error|failed)|QQml.*(error|failed)' "$log" >/dev/null; then
  fail_with_log "shell logged a Tomatask QML error"
fi

echo "runtime smoke test passed"
