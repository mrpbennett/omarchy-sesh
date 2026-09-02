#!/bin/bash

set -euo pipefail

# Remove all traces of omarchy-sesh from the user's system.
# Reverses bin/omarchy-sesh install, the systemd user unit, the Hyprland
# legacy autostart hook, power-menu overrides, session DB, lock, and logs.
# Idempotent: safe to rerun.

BIN="$HOME/.local/bin/omarchy-sesh"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
UNIT="$CONFIG_HOME/systemd/user/omarchy-sesh.service"
UNIT_WANTS="$CONFIG_HOME/systemd/user/graphical-session.target.wants/omarchy-sesh.service"
AUTOSAVE_UNIT="$CONFIG_HOME/systemd/user/omarchy-sesh-autosave.service"
AUTOSAVE_WANTS="$CONFIG_HOME/systemd/user/graphical-session.target.wants/omarchy-sesh-autosave.service"
AUTOSTART="$CONFIG_HOME/hypr/autostart.lua"
MENU="$CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
LEGACY_AUTOSTART="$HOME/.config/hypr/autostart.lua"
LEGACY_MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
STATE_DIR="$STATE_HOME/omarchy"
LOG_DIR="$STATE_DIR/log"
DB="$STATE_DIR/session.db"
LOCK="$STATE_DIR/session.lock"
RESTORE_MARKER="$STATE_DIR/restore-complete.json"
CURRENT_SESSION="$STATE_DIR/current-session.json"
INSTALL_MARKER="$STATE_DIR/sesh-installed"
MENU_CREATED_MARKER="$STATE_DIR/sesh-menu-created"

MARKER_COMMENT="# omarchy-sesh: restore saved windows after login (guard skips if already restored)"
LUA_MARKER_COMMENT="-- omarchy-sesh: restore saved windows after login (guard skips if already restored)"
RESTORE_LINE='hl.exec_cmd("sleep 2 && omarchy-sesh restore")'
SYSTEMCTL="${SYSTEMCTL:-systemctl}"

removed=0

validate_cleanup_directory() {
  local path="$1"
  if [[ -L "$path" ]]; then
    echo "error: refusing unsafe cleanup directory (symlink): $path" >&2
    return 1
  fi
  if [[ -e "$path" ]]; then
    if [[ ! -d "$path" ]]; then
      echo "error: refusing unsafe cleanup directory (not a directory): $path" >&2
      return 1
    fi
    if [[ $(stat -c '%u' -- "$path") != "$(id -u)" ]]; then
      echo "error: refusing unsafe cleanup directory (not user-owned): $path" >&2
      return 1
    fi
  fi
}

# Validate the parent first so no child lookup can follow an unsafe state link.
validate_cleanup_directory "$STATE_DIR"
validate_cleanup_directory "$LOG_DIR"

if ! "$SYSTEMCTL" --user stop omarchy-sesh-autosave.service omarchy-sesh.service >/dev/null 2>&1; then
  for unit in omarchy-sesh-autosave.service omarchy-sesh.service; do
    set +e
    "$SYSTEMCTL" --user is-active --quiet "$unit" >/dev/null 2>&1
    active_status=$?
    set -e
    case "$active_status" in
      0)
        echo "error: failed to stop active $unit" >&2
        exit 1
        ;;
      3|4) ;;
      *)
        echo "error: could not verify whether $unit stopped" >&2
        exit 1
        ;;
    esac
  done
fi
"$SYSTEMCTL" --user disable omarchy-sesh-autosave.service omarchy-sesh.service >/dev/null 2>&1 || true

for link in "$UNIT_WANTS" "$AUTOSAVE_WANTS"; do
  if [[ -L "$link" || -f "$link" ]]; then
    rm -f "$link"
    removed=1
  fi
done

if [[ -e "$UNIT" || -L "$UNIT" || -e "$AUTOSAVE_UNIT" || -L "$AUTOSAVE_UNIT" ]]; then
  rm -f "$UNIT" "$AUTOSAVE_UNIT"
  "$SYSTEMCTL" --user daemon-reload
  removed=1
fi

menu_paths=("$MENU")
[[ "$MENU" != "$LEGACY_MENU" ]] && menu_paths+=("$LEGACY_MENU")
for menu_path in "${menu_paths[@]}"; do
  if [[ -f "$menu_path" ]] && grep -qF "// omarchy-sesh: begin power-menu overrides" "$menu_path"; then
    python3 - "$menu_path" <<'PY'
import sys
from pathlib import Path
import os
import tempfile

path = Path(sys.argv[1]).resolve()
text = path.read_text()
begin = "// omarchy-sesh: begin power-menu overrides"
end = "// omarchy-sesh: end power-menu overrides"
begin_pos = text.find(begin)
end_pos = text.find(end, begin_pos)
if begin_pos < 0 or end_pos < 0:
    print(f"error: incomplete omarchy-sesh block in {path}", file=sys.stderr)
    raise SystemExit(1)
start = text.rfind("\n", 0, begin_pos) + 1
finish = text.find("\n", end_pos)
updated = text[:start] + text[finish + 1 if finish >= 0 else len(text):]
with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
    handle.write(updated)
    temporary = handle.name
os.chmod(temporary, path.stat().st_mode)
os.replace(temporary, path)
PY
    removed=1
  fi
done

if [[ -e "$BIN" || -L "$BIN" ]]; then
  rm -f "$BIN"
  removed=1
fi

autostart_paths=("$AUTOSTART")
[[ "$AUTOSTART" != "$LEGACY_AUTOSTART" ]] && autostart_paths+=("$LEGACY_AUTOSTART")
for autostart_path in "${autostart_paths[@]}"; do
  if [[ -f "$autostart_path" ]] && grep -qF -- "$RESTORE_LINE" "$autostart_path" \
    && { grep -qF -- "$MARKER_COMMENT" "$autostart_path" || grep -qF -- "$LUA_MARKER_COMMENT" "$autostart_path"; }; then
    python3 - "$autostart_path" "$MARKER_COMMENT" "$LUA_MARKER_COMMENT" "$RESTORE_LINE" <<'PY'
import sys
from pathlib import Path
import os
import tempfile

path = Path(sys.argv[1]).resolve()
markers = set(sys.argv[2:4])
restore_line = sys.argv[4]
lines = path.read_text().splitlines(keepends=True)
for index in range(len(lines) - 1):
    if (
        lines[index].rstrip("\r\n") in markers
        and lines[index + 1].rstrip("\r\n") == restore_line
    ):
        del lines[index : index + 2]
        break
with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
    handle.writelines(lines)
    temporary = handle.name
os.chmod(temporary, path.stat().st_mode)
os.replace(temporary, path)
PY
    removed=1
  fi
done

if [[ -f "$MENU_CREATED_MARKER" && -f "$MENU" ]]; then
  python3 - "$MENU" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1]).resolve()
if path.read_text().strip() == "{}":
    path.unlink()
PY
fi

state_artifacts=(
  "$DB" "$DB-wal" "$DB-shm" "$DB-journal" "$LOCK" "$RESTORE_MARKER"
  "$CURRENT_SESSION" "$INSTALL_MARKER" "$MENU_CREATED_MARKER"
)
for artifact in "${state_artifacts[@]}"; do
  if [[ -e "$artifact" || -L "$artifact" ]]; then
    rm -f -- "$artifact"
    removed=1
  fi
done

if [[ -d "$LOG_DIR" ]]; then
  rm -f "$LOG_DIR/omarchy-sesh.log"
  rmdir "$LOG_DIR" >/dev/null 2>&1 || true
  removed=1
fi

if (( removed )); then
  echo "omarchy-sesh: removed all installed traces."
else
  echo "omarchy-sesh: nothing to remove."
fi
