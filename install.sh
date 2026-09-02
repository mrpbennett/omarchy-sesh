#!/bin/bash

set -euo pipefail

# Install omarchy-sesh (user-level, no sudo): binary, systemd user units, and
# pre-shutdown Omarchy menu actions. Idempotent: safe to rerun.
# Uninstall with ./uninstall.sh.

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="${BIN_SRC:-$ROOT/bin/omarchy-sesh}"
UNIT_DIR_SRC="$ROOT/systemd/user"
PLUGIN_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/manifest.json")"

BIN="$HOME/.local/bin/omarchy-sesh"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$STATE_HOME/omarchy"
UNIT_DIR="$CONFIG_HOME/systemd/user"
INSTALL_MARKER="$STATE_DIR/sesh-installed"
MENU_CREATED_MARKER="$STATE_DIR/sesh-menu-created"
CURRENT_SESSION="$STATE_DIR/current-session.json"
AUTOSTART="$CONFIG_HOME/hypr/autostart.lua"
MENU="$CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
LEGACY_AUTOSTART="$HOME/.config/hypr/autostart.lua"
LEGACY_MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

MARKER_COMMENT="# omarchy-sesh: restore saved windows after login (guard skips if already restored)"
LUA_MARKER_COMMENT="-- omarchy-sesh: restore saved windows after login (guard skips if already restored)"
RESTORE_LINE='hl.exec_cmd("sleep 2 && omarchy-sesh restore")'
SYSTEMCTL="${SYSTEMCTL:-systemctl}"

for directory in "$STATE_DIR" "$STATE_DIR/log"; do
  if [[ -L "$directory" ]]; then
    echo "error: refusing unsafe state directory: $directory" >&2
    exit 1
  fi
  install -d -m 700 "$directory"
  chmod 700 "$directory"
done

for state_file in \
  "$STATE_DIR/session.db" \
  "$STATE_DIR/session.db-wal" \
  "$STATE_DIR/session.db-shm" \
  "$STATE_DIR/session.db-journal" \
  "$STATE_DIR/session.lock" \
  "$STATE_DIR/restore-complete.json" \
  "$CURRENT_SESSION" \
  "$STATE_DIR/log/omarchy-sesh.log" \
  "$INSTALL_MARKER" \
  "$MENU_CREATED_MARKER"; do
  if [[ -L "$state_file" || ( -e "$state_file" && ! -f "$state_file" ) ]]; then
    echo "error: refusing unsafe state file: $state_file" >&2
    exit 1
  fi
  [[ ! -f "$state_file" ]] || chmod 600 "$state_file"
done

[[ -f "$CURRENT_SESSION" ]] || install -m 600 /dev/null "$CURRENT_SESSION"

install_was_complete=0
autosave_was_enabled=0
[[ -f "$INSTALL_MARKER" ]] && install_was_complete=1
if "$SYSTEMCTL" --user is-enabled omarchy-sesh-autosave.service >/dev/null 2>&1; then
  autosave_was_enabled=1
fi

install -d "$(dirname "$BIN")"
install -m 755 "$BIN_SRC" "$BIN"
echo "installed $BIN"

install -d "$UNIT_DIR"
cp "$UNIT_DIR_SRC/omarchy-sesh.service" "$UNIT_DIR_SRC/omarchy-sesh-autosave.service" "$UNIT_DIR/"
echo "installed units to $UNIT_DIR"

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
    echo "removed legacy duplicate restore hook from $autostart_path"
  fi
done

if [[ "$MENU" != "$LEGACY_MENU" && -f "$LEGACY_MENU" ]] \
  && grep -qF "// omarchy-sesh: begin power-menu overrides" "$LEGACY_MENU"; then
  python3 - "$LEGACY_MENU" <<'PY'
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1]).resolve()
text = path.read_text()
begin = "// omarchy-sesh: begin power-menu overrides"
end = "// omarchy-sesh: end power-menu overrides"
begin_pos = text.find(begin)
end_pos = text.find(end, begin_pos)
if begin_pos < 0 or end_pos < begin_pos:
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
  echo "removed legacy power-menu overrides from $LEGACY_MENU"
fi

if [[ ! -f "$MENU" ]]; then
  install -d "$(dirname "$MENU")"
  printf '{}\n' >"$MENU"
  install -d "$(dirname "$MENU_CREATED_MARKER")"
  : >"$MENU_CREATED_MARKER"
  chmod 600 "$MENU_CREATED_MARKER"
fi

python3 - "$MENU" <<'PY'
import sys
from pathlib import Path
import json
import os
import re
import tempfile


def strip_comments(value):
    output = []
    index = 0
    quote = None
    while index < len(value):
        char = value[index]
        following = value[index + 1] if index + 1 < len(value) else ""
        if quote:
            output.append(char)
            if char == "\\" and following:
                output.append(following)
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue
        if char in ('"', "'"):
            quote = char
            output.append(char)
            index += 1
            continue
        if char == "/" and following == "/":
            while index < len(value) and value[index] != "\n":
                output.append(" ")
                index += 1
            continue
        if char == "/" and following == "*":
            output.extend("  ")
            index += 2
            while index < len(value):
                if value[index:index + 2] == "*/":
                    output.extend("  ")
                    index += 2
                    break
                output.append("\n" if value[index] == "\n" else " ")
                index += 1
            continue
        output.append(char)
        index += 1
    return "".join(output)


def atomic_write(path, value):
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        handle.write(value)
        temporary = handle.name
    os.chmod(temporary, path.stat().st_mode)
    os.replace(temporary, path)

path = Path(sys.argv[1]).resolve()
text = path.read_text()
begin = "// omarchy-sesh: begin power-menu overrides"
end = "// omarchy-sesh: end power-menu overrides"
if (begin in text) != (end in text):
    print(f"error: incomplete omarchy-sesh block in {path}", file=sys.stderr)
    raise SystemExit(1)
base = text
if begin in text:
    if text.count(begin) != 1 or text.count(end) != 1:
        print(f"error: duplicate omarchy-sesh blocks in {path}", file=sys.stderr)
        raise SystemExit(1)
    begin_pos = text.find(begin)
    end_pos = text.find(end, begin_pos)
    if end_pos < begin_pos:
        print(f"error: reversed omarchy-sesh block in {path}", file=sys.stderr)
        raise SystemExit(1)
    start = text.rfind("\n", 0, begin_pos) + 1
    finish = text.find("\n", end_pos)
    base = text[:start] + text[finish + 1 if finish >= 0 else len(text):]

code = strip_comments(base)

actions = {
    "system.logout": ('󰍃', "Logout", "omarchy-system-logout"),
    "system.reboot": ('󰜉', "Reboot", "omarchy-system-reboot"),
    "system.shutdown": ('󰐥', "Shutdown", "omarchy-system-shutdown"),
}
entries = []
for menu_id, (icon, label, command) in actions.items():
    if re.search(rf'"{re.escape(menu_id)}"\s*:', code):
        print(f"warning: preserving customized {menu_id} action")
        continue
    action = (
        '"$HOME/.local/bin/omarchy-sesh" save --label logout --wait || true; '
        f"exec {command}"
    )
    payload = json.dumps(
        {"icon": icon, "label": label, "action": action},
        ensure_ascii=False,
        separators=(",", ":"),
    )
    entries.append(f'  "{menu_id}": {payload},')

updated = base
if entries:
    root = re.search(r"(?m)^[ \t]*\{", code)
    if root is None:
        print(f"error: {path} is not a JSONC object", file=sys.stderr)
        raise SystemExit(1)

    items = re.search(r'"items"\s*:\s*\{', code)
    target = items or root
    indent = "    " if items else "  "
    block = "\n" + indent + begin + "\n" + "\n".join(entries) + "\n" + indent + end + "\n"
    updated = base[: target.end()] + block + base[target.end() :]
if updated != text:
    atomic_write(path, updated)
    print(f"updated pre-shutdown saves in {path}")
PY

"$SYSTEMCTL" --user daemon-reload
"$SYSTEMCTL" --user enable omarchy-sesh.service >/dev/null
if (( ! install_was_complete || autosave_was_enabled )); then
  "$SYSTEMCTL" --user enable omarchy-sesh-autosave.service >/dev/null
  if (( autosave_was_enabled )); then
    "$SYSTEMCTL" --user try-restart omarchy-sesh-autosave.service >/dev/null
  fi
  echo "enabled omarchy-sesh.service and omarchy-sesh-autosave.service"
else
  echo "enabled omarchy-sesh.service; preserved manual autosave mode"
fi

install -d -m 700 "$(dirname "$INSTALL_MARKER")"
printf '%s\n' "$PLUGIN_VERSION" >"$INSTALL_MARKER"
chmod 600 "$INSTALL_MARKER"

echo "omarchy-sesh: installed. Restore runs on next login; saves run before power-menu actions and periodically."
