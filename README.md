# OmarchySesh
The plugin you didn't know you need till you have it. Restores window positions and running apps after reboot or shutdown on Omarchy (Hyprland). 

Snapshots live in a SQLite DB at: `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/session.db`.

## Installing as an Omarchy Plugin

The plugin is published as an Omarchy bar widget with manifest id
`mrpbennett.sesh` (kind `bar-widget`). Use the Omarchy plugin manager instead of
running `install.sh` by hand.

### Install

```sh
omarchy plugin add https://github.com/mrpbennett/omarchy-sesh.git --enable
```

What happens:

1. Omarchy clones the repository into a staging directory.
2. It validates the folder against the Omarchy plugin manifest schema
   (`omarchy plugin validate`); invalid plugins are refused.
3. It reads the manifest id (`mrpbennett.sesh`) and moves the checkout to
   `~/.config/omarchy/plugins/mrpbennett.sesh/`.
4. It rescans shell plugins and, because the manifest declares a bar widget,
   asks which bar section to place it in (default `right`).
5. It enables the widget with `omarchy plugin enable mrpbennett.sesh --section <section>`.

Verify placement with:

```sh
omarchy plugin list
```

To update a git-managed plugin:

```sh
omarchy plugin update mrpbennett.sesh
```

To remove it, see [Uninstall](#uninstall).

### First Use

The bar widget is a button showing a session icon. Opening its panel on a fresh
install runs the plugin's installation check: it verifies the CLI binary, the
two systemd user units, and the version marker. If any are missing, it runs the
bundled `install.sh` automatically, which deploys (user-level, no sudo):

- `~/.local/bin/omarchy-sesh`
- `~/.config/systemd/user/omarchy-sesh.service` and
  `omarchy-sesh-autosave.service`
- marker-delimited pre-shutdown save actions in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`, preserving any
  user-customized logout, reboot, and shutdown actions

After installation the widget shows three actions:

- **Active** — enables periodic autosave (default interval 60s).
- **Manual** — disables autosave and saves the current session immediately.
- **Restore** — flips the panel around to the named-session list.

The session list turns back to the three actions with Escape or the back arrow.
Each row carries two actions:

- **Play** — restores that named session (Enter also restores the selected row).
- **Delete** — asks for confirmation, then removes the named session and its
  snapshot from the database (`x` on the selected row does the same). The
  confirmation defaults to Cancel; Left/Right or Tab switches buttons, Enter
  answers, Escape cancels. Deleting cannot be undone.

The panel header labels the current state as `auto` while autosave is active;
in Manual mode it shows `manual` or the name recorded by the best-effort
current-session metadata. Deleting that named session attempts to clear the
label.
If the mode cannot be determined, the header shows `unavailable`.

On a fresh install autosave defaults to Active mode. Selecting **Manual**
disables periodic autosave and captures the current desktop immediately;
selecting **Active** again captures a new baseline only when no successful
restore marker exists, then re-enables the periodic saver. A restore runs at the
next graphical login via `omarchy-sesh.service`;
the autosave service is ordered after it and waits one interval before its first
capture.
Saves before logout, reboot, or shutdown happen synchronously so the reboot
snapshot is never superseded by a periodic capture during teardown.

See [How it works](#how-it-works) for the full save/restore behavior and
`install.sh`/`Service.qml` for the installation and first-open wiring.

## CLI

```sh
omarchy-sesh save [--label LABEL] [--name NAME]                         # snapshot current windows
omarchy-sesh restore [--name NAME] [--dry-run] [--timeout SECONDS]      # restore latest or named snapshot
omarchy-sesh autosave [--interval 60]                                   # periodic save (crash cover)
omarchy-sesh status                                                     # list saved sessions
omarchy-sesh list [--json]                                              # list named sessions
omarchy-sesh delete --name NAME                                         # delete a named session
omarchy-sesh mode [active|manual] [--json]                              # query/change mode and current session
omarchy-sesh acceptance [--expect-power-save|--expect-restore-failure]  # live acceptance evidence only
```

Config (optional): `${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/sesh/config.json`

```json
{
  "exclude_classes": ["polkit-gnome-authentication-agent-1"],
  "autosave_seconds": 60,
  "restore_timeout_seconds": 20,
  "snapshot_retention": 5,
  "monitor_fallback": "focused"
}
```

`exclude_classes` must be an array of non-empty strings. Autosave and retention
must be positive integers, and the restore timeout must be at least 2 seconds so
a launch group can retry at least once. `monitor_fallback` accepts `"focused"`,
`"lowest"`, or a connector-shaped name such as `"DP-2"`; any other string is
rejected rather than treated as an unknown monitor. Each retention slot applies
separately to complete and diagnostic snapshots.

Only `save`, `restore`, and `autosave` load this configuration. Unknown settings,
invalid JSON, and invalid values are reported consistently but acted on
differently, because a bad config must never cost you a session. `restore` fails
closed: it reports the error, exits 2, and changes nothing, and its service does
not restart-loop. `save` and `autosave` log the error and continue with the
built-in defaults, so a typo cannot skip the logout snapshot or silently stop
periodic saves. If those commands cannot read the file at all, they log the
transient error and continue with the defaults. `status`, `list`, `delete`,
`mode`, and `acceptance` do not load it.

## Dependencies

- `hyprctl` — queried (`-j`) for clients, monitors, and workspaces, and
  invoked to relaunch/place windows during restore.
- `bash` — runs `install.sh`/`uninstall.sh`.
- `python3` (stdlib only: `sqlite3`, `json`, `shlex`) — implements the
  `omarchy-sesh` CLI.
- `/proc/<pid>/{cmdline,cwd}` — read directly to capture each window's
  launch command and working directory.
- systemd user units (`omarchy-sesh.service`,
  `omarchy-sesh-autosave.service`) — installed to drive restore-on-login and
  periodic autosave.

No network calls and no non-stdlib QML imports. See
[Requirements](#requirements) for version constraints.

## How it works

**Save** (`omarchy-sesh save`) queries clients, monitors, and workspaces through
`hyprctl -j`, filters out unmapped windows and excluded classes, and reads each
remaining window's real command line and cwd from `/proc/<pid>/{cmdline,cwd}`.
Position, size, workspace, monitor connector and description, and
floating/fullscreen/pinned state are captured alongside the launch command and
written as one `sessions` row plus window and workspace-layout rows in the
SQLite DB. Complete Hyprland group membership and member order are translated
from live addresses to snapshot-local metadata. Windows sharing a saved PID are
kept as one launch group, except recognized terminal windows and Chromium web
apps, which launch individually. By default, the latest five complete and five
diagnostic snapshots are retained; retention is configurable.

Complete command lines can contain credentials supplied as arguments. The
state and log directories are therefore owner-only (`0700`), and runtime state
files, including the SQLite database and sidecars, are owner-only (`0600`). The
installer and CLI repair older permissive modes automatically. Restore failure
logs omit launch commands; `restore --dry-run` intentionally prints them to the
calling terminal for inspection.

Snapshot history owns SQLite migration, atomic writes, selection, retention,
and named-session deletion. It returns immutable Snapshots whose windows use
their order within that Snapshot as identity, rather than a database row ID.
The schema is version 7; existing databases migrate in place.

**Named save** (`omarchy-sesh save --name NAME`) captures the same state as a
manual save and assigns it a unique name. Named sessions are independent from
the automatic boot snapshot: they are retained until explicitly deleted and
are restored only with `omarchy-sesh restore --name NAME`. `omarchy-sesh list`
shows named sessions and `omarchy-sesh delete --name NAME` removes a name and
its saved window state. Saving an existing name fails; delete it before using
that name again. Names may contain internal spaces but cannot be empty, padded
with whitespace, contain control characters, or exceed 128 characters.
The panel's **Restore** action lists these named sessions; create them from the
CLI until a named-save panel action is added.

After a successful named save or restore, the CLI attempts to keep the current
name in
`${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current-session.json` for the
panel. An ordinary manual save or automatic restore attempts to clear it,
periodic saves leave it alone, and deleting the current named session attempts
to clear it.
These updates are best-effort secondary panel metadata: failures are logged but
do not fail an otherwise successful save, restore, or delete. Installation
creates the file owner-only, upgrades repair its permissions, and uninstall
removes it. `mode --json` reports both the autosave mode and this best-effort
name.

**Restore** (`omarchy-sesh restore`) loads the most recent complete session;
a healthy empty session intentionally restores nothing. An advisory lock
serializes restore and save operations. Existing windows are consumed
one-to-one using class, title, and workspace, and class multiplicities prevent
false already-restored matches. All missing saved PID groups launch immediately
via Hyprland's Lua dispatch API, then windows are matched and placed as they
appear during one shared bounded polling window. If a process does not recreate
all of its saved windows, its command is retried independently. Chromium app-mode
windows are restored individually through
Omarchy's web-app launcher because Chromium does not reopen them from the base
browser command. After matching, eligible nested dwindle workspaces are rebuilt
in one fast Lua evaluation: one seed remains on the target workspace while the
other leaves pass through a temporary staging workspace. Focus, insertion
direction, and split ratios recreate the saved geometry, which is then verified.
Eligible two-window dwindle workspaces set their saved split ratio directly and
also verify both resulting rectangles, so a 30/70 split is not silently accepted
as Hyprland's default 50/50 split.
Alacritty, Foot, Ghostty, Kitty, and WezTerm use canonical one-window launch
commands instead of replaying saved daemon or server commands. Each saved
terminal OS window launches independently; indistinguishable terminal windows
serialize only long enough to correlate their new addresses. The saved emulator
is preserved, while a shared server cwd is omitted because it cannot be
attributed safely to one window.
Each saved workspace returns to the same connected monitor; renamed or rewired
outputs are identified by monitor description. Workspaces from disconnected
displays use the configured fallback: the focused monitor then the lowest
monitor ID by default, the lowest monitor directly, or a preferred connector.
An unavailable preferred connector safely returns to the default policy.
Floating windows temporarily leave pinned/fullscreen state when necessary,
resize before moving, and then return to their saved state. Restore verifies
their final compositor geometry after a short settling interval and reapplies
one mismatched placement pass.
Tiled ratio correction also waits for Hyprland to settle and retries one
accepted mismatch before reporting degraded geometry.
`--dry-run` prints the launch plan without executing it.

Restore prepares one immutable Restore run from the selected Snapshot and its
initial live observation. Its preview is repeatable and effect-free; execution
is single-use. Production Hyprland IPC is behind an adapter that exposes the
same semantic observations, actions, and typed results used by deterministic
tests. Transport and temporarily unavailable storage, capture, focus,
placement, monitor, or replay operations exit 75 so systemd may retry. Rejected
operations and other permanent failures exit 1 and do not restart-loop. A
complete restore exits 0; a degraded restore exits 0 with a warning; an
incomplete restore exits 1 and keeps autosave gated. The panel supplies a
10-second timeout. Startup supplies 60 seconds and retries incomplete runs only
after a persisted 30-second observation grace period.

On Hyprland 0.56 or newer, complete and uniquely matched window groups are
re-formed in saved member order after placement. Partial or ambiguous groups,
unrelated existing groups, and groups containing fullscreen or pinned windows
are left unchanged. Hyprland does not expose the saved active tab or lock/deny
state; reconstructed groups select their first saved member. Hyprland 0.55
continues to restore the windows without grouping them.

**Autosave** (`omarchy-sesh autosave`) waits one interval before its first
capture, then saves periodically (default 60s, configurable). It remains gated
while restore is incomplete, so a partial login cannot replace the reboot snapshot,
and refreshes the active Hyprland instance before every capture. Explicitly
selecting Active mode captures the current desktop first when no successful
restore marker exists. A synchronous logout, reboot, or shutdown save closes
the gate before capture so a periodic save cannot supersede it during teardown.

Exact dwindle tree replay, including two-window ratios, requires a schema-v5
snapshot, `dwindle:use_active_for_splits =
true`, `dwindle:preserve_split = true`,
`dwindle:permanent_direction_override = false`, every saved tiled window to be
present and uniquely identified, no unrelated tiled occupants, unchanged
workspace dimensions, and geometry with one unambiguous recursive split. Apps
continue to launch in parallel. Replay runs independently per workspace and
restores the focused window or empty workspace afterward; because Hyprland
layout messages act on the focused workspace, a very brief workspace change may
still be visible during login.
Ineligible workspaces retain the guarded two-window and compatible-slot
fallback without moving unrelated windows. Hyprland's `stableId` is only a live
compositor window-object selector and resets with Hyprland, so ambiguous
same-class windows still depend on title and workspace metadata. See
`docs/session-restore-spec.md` for the full design rationale and limitations.
When a disconnected display falls back to a monitor with different dimensions,
saved floating coordinates may require manual adjustment.

## Requirements

- Hyprland >= 0.55 (uses the Lua dispatch API)
- python3 (stdlib only — sqlite3, json, shlex)

Exact dwindle tree replay requires Hyprland >= 0.56 with the three dwindle options
listed above. Ordinary restore remains available when those conditions are not
met.

## Uninstall

Omarchy does not run lifecycle hooks when removing plugins. For a plugin
installation, uninstall the session services before removing the checkout:

```sh
${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/mrpbennett.sesh/uninstall.sh
omarchy plugin remove mrpbennett.sesh
```

For a direct repository installation, run:

```sh
./uninstall.sh
```

Removes every trace: the binary, both systemd user units and their enablement,
legacy Hyprland hook, marker-delimited power-menu overrides, session DB,
operation lock, restore and current-session markers, and logs. User-authored
configuration is preserved. Idempotent and safe to rerun.

## Development roadmap

See `docs/future-improvements.md` for the full roadmap, including live reboot
acceptance, stable window identity, window groups, configuration, and upgrade
coverage.

## Live Reboot Acceptance

`omarchy-sesh acceptance` never performs a live save or restore, changes mode,
or invokes a power action. Like every CLI invocation, startup may create or
repair owner-only runtime state and migrate legacy XDG state, so it is not
strictly read-only. Follow
`docs/live-acceptance.md` for the controlled reboot, power-menu, and
failure-recovery procedures.

## License

MIT — see [LICENSE](LICENSE).
