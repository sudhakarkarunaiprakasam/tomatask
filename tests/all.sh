#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

node_bin="${NODE_BIN:-}"
if [[ -z $node_bin ]]; then
  node_bin=$(command -v node || true)
fi
if [[ -z $node_bin ]] && command -v mise >/dev/null 2>&1; then
  node_bin=$(mise which node 2>/dev/null || true)
fi
if [[ -z $node_bin ]]; then
  node_bin="${HOME}/.local/share/mise/installs/node/latest/bin/node"
fi

if [[ -z $node_bin ]]; then
  echo "node not found: add Node to PATH or install with mise"
  exit 1
fi

if ! "$node_bin" "$ROOT/tests/timer-model.test.js"; then
  echo "failed to run node from '$node_bin'"
  exit 1
fi

if [[ -n ${OMARCHY_PATH:-} && -x $OMARCHY_PATH/bin/omarchy ]]; then
  if PATH="$OMARCHY_PATH/bin:$PATH" "$OMARCHY_PATH/bin/omarchy" commands --all 2>/dev/null | grep -q "plugin validate"; then
    PATH="$OMARCHY_PATH/bin:$PATH" "$OMARCHY_PATH/bin/omarchy" plugin validate "$ROOT"
  else
    echo "skipping plugin validation (omarchy CLI does not support 'plugin validate')"
  fi
else
  echo "skipping plugin validation (set OMARCHY_PATH to an Omarchy checkout)"
fi

if command -v qmllint >/dev/null 2>&1 && [[ -n ${OMARCHY_PATH:-} && -d $OMARCHY_PATH/shell ]]; then
  qmllint -I "$OMARCHY_PATH/shell" "$ROOT/Service.qml" "$ROOT/BarWidget.qml" "$ROOT/Panel.qml"
else
  echo "skipping qmllint (set OMARCHY_PATH to an Omarchy checkout)"
fi

"$ROOT/tests/runtime-smoke.sh"

echo "all tests passed"
