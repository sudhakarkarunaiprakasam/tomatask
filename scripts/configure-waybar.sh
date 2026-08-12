#!/usr/bin/env bash
# Adds a "custom/tomatask" module to the user's Waybar config.jsonc so the
# Pomodoro timer shows up without any manual editing.
#
# Safe by design:
#   - No-op if custom/tomatask is already present (idempotent)
#   - Always writes a timestamped backup before touching the real file
#   - Validates the result is well-formed JSON(C) before committing it
#   - Supports --dry-run to preview the change without writing anything
set -euo pipefail

CONFIG="${WAYBAR_CONFIG:-$HOME/.config/waybar/config.jsonc}"
DRY_RUN=0

for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    --config=*) CONFIG="${arg#--config=}" ;;
    *)
      echo "Unknown option: ${arg}" >&2
      echo "Usage: $0 [--dry-run] [--config=/path/to/config.jsonc]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${CONFIG}" ]]; then
  echo "Waybar config not found at: ${CONFIG}" >&2
  echo "Set WAYBAR_CONFIG or pass --config=/path/to/config.jsonc" >&2
  exit 1
fi

if grep -q '"custom/tomatask"' "${CONFIG}"; then
  echo "custom/tomatask is already configured in ${CONFIG} - nothing to do."
  exit 0
fi

TARGET_ARRAY=""
for arr in modules-right modules-center modules-left; do
  if grep -q "\"${arr}\"[[:space:]]*:" "${CONFIG}"; then
    TARGET_ARRAY="${arr}"
    break
  fi
done

if [[ -z "${TARGET_ARRAY}" ]]; then
  echo "Could not find modules-left/modules-center/modules-right in ${CONFIG}." >&2
  echo "Please add the custom/tomatask module manually - see README.md." >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

python3 - "${CONFIG}" "${TARGET_ARRAY}" "${TMP}" <<'PYEOF'
import re
import sys

config_path, target_array, tmp_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(config_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1) Add "custom/tomatask" as the first entry of the chosen modules-* array.
array_pattern = re.compile(r'("' + re.escape(target_array) + r'"\s*:\s*\[)')
new_text, count = array_pattern.subn(
    lambda m: m.group(1) + ' "custom/tomatask",', text, count=1
)
if count != 1:
    print(f"Failed to locate {target_array} array", file=sys.stderr)
    sys.exit(1)

# 2) Insert the module definition as a new top-level key, right after the
#    root object's opening '{'.
module_block = (
    "\n"
    '  "custom/tomatask": {\n'
    '    "exec": "tomatask-status",\n'
    '    "interval": 1,\n'
    '    "return-type": "json",\n'
    '    "on-click": "tomatask"\n'
    "  },"
)
brace_index = new_text.index("{")
new_text = new_text[: brace_index + 1] + module_block + new_text[brace_index + 1:]

with open(tmp_path, "w", encoding="utf-8") as f:
    f.write(new_text)
PYEOF

# Best-effort validation that the result is still well-formed JSON once
# comments are stripped (Waybar's config.jsonc allows // and /* */ comments).
python3 - "${TMP}" <<'PYEOF'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    text = f.read()

no_block_comments = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
no_line_comments = re.sub(r"(?m)(^|[^:])//.*$", r"\1", no_block_comments)
try:
    json.loads(no_line_comments)
except json.JSONDecodeError as exc:
    print(f"Resulting config is not valid JSON(C): {exc}", file=sys.stderr)
    sys.exit(1)
PYEOF

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "--- dry run: showing changes, nothing written ---"
  diff -u "${CONFIG}" "${TMP}" || true
  exit 0
fi

BACKUP="${CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
cp "${CONFIG}" "${BACKUP}"
cp "${TMP}" "${CONFIG}"

echo "Added custom/tomatask to \"${TARGET_ARRAY}\" in ${CONFIG}"
echo "Backup saved at ${BACKUP}"
echo "Run 'omarchy restart waybar' to apply the change."
