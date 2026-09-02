# Omarchy Session Restore — Design Spec

## 1. Goal and honest scope

**Goal:** after reboot or shutdown, relaunch the apps that were open and put each
window back where it was.

**What this can achieve (the ceiling):**

| Aspect | Outcome |
|---|---|
| App relaunch | Exact — reconstruct launch command from `/proc/<pid>/cmdline` + cwd |
| Floating window geometry | Exact — Hyprland dispatchers place/resize by pixel |
| Tiled window placement | Best-effort — complete, uniquely matched two-window ratios and unambiguous nested dwindle layouts are restored and verified. Compatible-slot correction remains the fallback. Hyprland still exposes no split-tree import/export API |
| Workspace assignment | Yes — launch into the saved workspace and move the matched window there |
| Monitor remapping | Yes — connector name, physical description, then deterministic fallback |
| Window flags (float/fullscreen/pinned) | Yes — `hl.dsp.window.float`, `fullscreenstate`, `pin` |
| App *content* (tabs, unsaved docs, shell sessions) | No — that is application-owned. Browsers/tmux/editors restore their own content |

**Why:** Wayland's `xdg-shell` removed client-set window positions — the
compositor owns placement. Hyprland has no native session restore (no
`hyprctl restore`; `misc:allow_session_lock_restore` is unrelated; `persistent`
workspace rules only keep *empty* workspaces alive). The 2026
`xx-session-management-v1` protocol is the only real fix and Hyprland has not
implemented it. So restore is an external tool that reads a saved snapshot and
drives `hyprctl`.

## 2. Architecture

```
┌────────────────────────────────────────────────────────────┐
│  omarchy-sesh (single Python script, ~/.local/bin)        │
│                                                            │
│  save:    hyprctl -j clients  +  /proc/<pid>  →  sqlite    │
│  restore: sqlite                →  hyprctl dispatchers     │
└────────────────────────────────────────────────────────────┘
         ▲                        │
   started by               fires on startup,
   systemd service          logout, power menu
```

No Omarchy or Hyprland source change. Storage is sqlite at
`${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/session.db` (a plain host file — not something
Hyprland reads; Hyprland has no read path). CLI Snapshot history owns all
database reads and writes; the autosave daemon is one of its writers.

The single script contains two deep modules:

- **Snapshot history** owns the complete persistence seam: schema migration,
  connections and transactions, storage error classification, Snapshot
  recording and selection, retention, summaries, and named-session deletion.
  Its interface accepts immutable capture values and returns immutable
  Snapshots; callers do not coordinate SQL or transaction boundaries.
- **Restore run** owns one prepared restore attempt. `prepare` freezes the
  selected Snapshot, settings, initial observation, matches, launch groups, and
  preview into one immutable plan. `preview` is repeatable and effect-free;
  `execute` is single-use and owns matching, concurrent launch scheduling, the
  shared deadline, placement/correction order, verification, and its typed
  outcome. The save, restore, and autosave command paths retain configuration
  loading; commands retain operation locks, restore and current-session markers,
  terminal output, and exit translation.

Restore run depends on a semantic Hyprland interface for capture, observation,
actions, mutation scope, and typed results. `ProductionHyprland` is the IPC
adapter; Lua generation, live selectors, command redaction, monitor refresh
after workspace movement, and animation lifetime remain local to it.
`DeterministicHyprland` implements the same interface with in-memory state,
queued results, replay modeling, and ordered events. This seam gives tests high
leverage while preserving module depth and production locality.

Verified against Hyprland 0.56.2 (Lua dispatch API, not the pre-0.55 hyprlang
dispatchers). Key facts confirmed live:

- `hyprctl -j clients` returns per window: `address`, `at [x,y]`, `size [w,h]`,
  `workspace {id,name}`, `monitor` (id), `class`, `title`, `initialClass`,
  `initialTitle`, `pid`, `floating`, `pinned`, `fullscreen`, `fullscreenClient`,
  `grouped`, `tags`, `stableId`, `xwayland`, `mapped`, `hidden`.
  `fullscreen` encoding: `0` none, `1` maximized, `2` fullscreen.
- `hyprctl -j workspaces` returns `id`, `name`, `monitor`, `tiledLayout`,
  `lastwindowtitle`, `ispersistent`.
- **Launch with rules** (0.56 Lua form — the old `[workspace N silent]` prefix
  is NOT honored by `exec_cmd`):
  `hyprctl dispatch 'hl.dsp.exec_cmd("<cmd>", { workspace = "<N> silent", float = true })'`
  Returns `ok`, no PID — the spawned window must be discovered by polling
  `hyprctl -j clients` for a new address.
- **Placement dispatchers** (0.56 Lua form, all accept `window =
  "address:0x…"`):
  - `hl.dsp.window.move({ x = <abs_x>, y = <abs_y>, window = … })` — absolute
    position; add `relative = true` for delta.
  - `hl.dsp.window.resize({ x = <w>, y = <h>, window = … })` — exact size.
    **Important:** resize is center-anchored, so resize *then* move for
    pixel-exact placement.
  - `hl.dsp.window.float({ action = "on", window = … })`
  - `hl.dsp.window.fullscreen_state({ internal = <0|1|2>, client = <0|1|2>, window = … })`
  - `hl.dsp.window.pin({ window = … })` (floating only)
  - `hl.dsp.window.swap({ window = …, target = … })` — exchange two tiled
    windows while retaining their layout slots
  - `hl.dsp.window.move({ workspace = <N>, follow = false, window = … })` —
    silent workspace move
  - `hl.dsp.workspace.move({ workspace = <N>, monitor = "<NAME>" })` — move a
    workspace to a monitor (workspace must exist first)
- **Runtime configuration** (0.56): `hyprctl keyword <option> <value>` is NOT
  usable — it answers "keyword can't work with non-legacy parsers. Use eval."
  and still exits 0, so its failure is silent. Read options with
  `hyprctl -j getoption <option>` or `hl.get_config("<option>")`, and write them
  with `hyprctl eval 'hl.config({ <section> = { <key> = <value> } })'`. Always
  read the value back, because a rejected write is not reported.
- UWSM caveat (Omarchy uses `uwsm-app`): **never** trigger restore or save via
  the `exit` dispatcher or by killing Hyprland — use `uwsm stop` / loginctl so
  session teardown stays ordered.

## 3. Storage schema (sqlite)

DB path: `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/session.db`.

The complete command line is required for relaunch and may contain credentials.
Create and repair the state and log directories as `0700`; create and repair the
database, WAL/SHM/journal sidecars, lock, restore marker, and log as `0600`.
Reject symlinked or non-user-owned state storage rather than writing through it.
CLI processes and both systemd units use a `0077` umask as defense in depth.
Installation creates the current-session marker at
`${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current-session.json` owner-only,
upgrades repair its permissions, and uninstall removes it. Atomic operation-time
replacement is best-effort secondary panel metadata rather than a prerequisite
for save, restore, or delete success.

```sql
PRAGMA journal_mode = WAL;

-- One row per saved window. Per-run addresses are never persisted because
-- addresses change every launch.
CREATE TABLE windows (
    id            INTEGER PRIMARY KEY,     -- storage identity; not exposed by a Snapshot
    session       INTEGER NOT NULL,         -- FK -> sessions.id
    ord           INTEGER NOT NULL,         -- Snapshot-local window identity and order
    class         TEXT NOT NULL,            -- client class
    title         TEXT,
    initial_class TEXT,
    initial_title TEXT,
    cmdline       TEXT NOT NULL,            -- argv join(' ') from /proc/pid/cmdline
    cwd           TEXT,                     -- /proc/pid/cwd
    workspace_id  INTEGER,                  -- numeric workspace at save time
    workspace_name TEXT,
    monitor_name  TEXT,                     -- hyprctl monitor name (e.g. DP-2)
    monitor_description TEXT,                -- physical display description
    at_x          INTEGER, at_y INTEGER,    -- exact float position or tiled slot metadata
    size_w        INTEGER, size_h INTEGER,
    floating      INTEGER NOT NULL DEFAULT 0,
    fullscreen    INTEGER NOT NULL DEFAULT 0,  -- 0/1/2
    pinned        INTEGER NOT NULL DEFAULT 0,
    xwayland      INTEGER NOT NULL DEFAULT 0,
    pid           INTEGER,                  -- groups windows from one process
    group_id      INTEGER,                  -- snapshot-local Hyprland group
    group_ord     INTEGER,                  -- zero-based saved member order
    FOREIGN KEY (session) REFERENCES sessions(id)
);

CREATE TABLE sessions (
    id        INTEGER PRIMARY KEY,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    label     TEXT,                      -- 'manual' | 'logout' | 'periodic'
    capture_status TEXT NOT NULL DEFAULT 'complete', -- complete | partial | failed | legacy_unknown
    capture_error TEXT
);

-- Stable user-visible names for explicitly saved sessions. The referenced
-- session owns the captured window and workspace-layout rows.
CREATE TABLE named_sessions (
    name       TEXT PRIMARY KEY,
    session    INTEGER NOT NULL UNIQUE,
    FOREIGN KEY (session) REFERENCES sessions(id)
);

CREATE TABLE workspace_layouts (
    session      INTEGER NOT NULL,
    workspace_id INTEGER NOT NULL,
    layout       TEXT,
    at_x         INTEGER, at_y INTEGER,
    size_w       INTEGER, size_h INTEGER,
    work_x       INTEGER, work_y INTEGER,
    work_w       INTEGER, work_h INTEGER,
    gap_top      INTEGER, gap_right INTEGER,
    gap_bottom   INTEGER, gap_left INTEGER,
    complete     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (session, workspace_id),
    FOREIGN KEY (session) REFERENCES sessions(id)
);

PRAGMA user_version = 6;
```

Rules:
- Restore selects the newest `complete` capture. A healthy zero-window capture
  is authoritative; partial, failed, and ambiguous legacy captures are never
  restore sources.
- Named snapshots are complete captures referenced by `named_sessions`. They
  are excluded from automatic latest-session selection and ordinary retention;
  `restore --name NAME` selects one explicitly. A name may be created only
  once, and `delete --name NAME` removes its snapshot, windows, and layouts.
  Names cannot be empty, padded with whitespace, contain control characters,
  or exceed 128 characters.
- Only save windows with `mapped == true` and non-empty `cmdline`. Drop the
  Omarchy shell, bars, panels, trays, polkit agents, and whatever the
  autostart already launches (exclude list in config, see §6).
- A window address is never persisted as a lookup key. Saved PIDs group launch
  commands only; restore-time windows are matched one-to-one by class, title,
  initial metadata, and workspace.
- Snapshot history selects window rows in `ord` order and materializes immutable
  `SnapshotWindow` values. Restore algorithms identify a window by that
  snapshot-local order; SQLite row and foreign-key identities do not cross the
  module interface.
- `clients[].grouped` addresses are translated to nullable snapshot-local
  `group_id` and `group_ord` values only when every ordered member was captured
  and every member reports the same group. Incomplete or malformed groups are
  saved as ordinary ungrouped windows.
- Workspace layout rows exist only when at least two ordinary tiled windows have
  complete geometry. They retain client bounds, the logical work area after
  global outer gaps, and directional inner gaps so inferred ratios account for
  visible spacing. `complete` requires every mapped, non-fullscreen tiled client
  on that workspace to be captured. Legacy snapshots and snapshots with
  workspace-specific rules remain valid but are ineligible for nested replay.

## 4. Save path (`omarchy-sesh save`)

1. Query `hyprctl -j clients`, `monitors`, and `workspaces`.
2. For each, read `/proc/<pid>/cmdline` and `/proc/<pid>/cwd` (resolve cwd
   symlink). Skip windows whose cmdline is empty, is `hyprctl`, or is in the
   exclude list.
3. Group windows by saved PID. Determine numeric `workspace_id`; resolve the
   monitor connector name and description via `hyprctl -j monitors` (map
   `monitor` id to its monitor record). Retain `at` and `size` for tiled windows
   as slot identity metadata and inputs to guarded post-launch sizing.
4. Record the tiled layout name, tiled client bounds, and per-workspace capture
   completeness, then pass one immutable capture to Snapshot history. The
   module inserts the session, window, workspace-layout, and optional name rows,
   and applies retention in one transaction.
5. When `--name NAME` is supplied, reject an existing name before capture and,
   only for a complete capture, insert its `named_sessions` reference in the
   same transaction. Named sessions are not an automatic boot restore source.

Triggers (any one fires a save):

| Trigger | Mechanism |
|---|---|
| Clean logout / reboot / shutdown | Power-menu entries (see §6) run `omarchy-sesh save` before `uwsm stop` / `loginctl` |
| Systemd teardown diagnostic | `ExecStop=omarchy-sesh save --teardown`; never supersedes a healthy snapshot |
| Periodic (crash cover) | systemd daemon, every 60 s, writes a `periodic` snapshot |

## 5. Restore path (`omarchy-sesh restore`)

Runs once from the systemd user service. Startup IPC failures return nonzero;
the service retries after two seconds.

1. Acquire an advisory operation lock and ask Snapshot history for the newest
   complete Snapshot,
   or the complete snapshot for `--name NAME`. Automatic restore never selects
   a named snapshot.
   A complete empty Snapshot restores nothing. Prepare one immutable Restore
   run from the Snapshot, validated settings, and initial client observation.
   Preparation matches existing windows one-to-one, compares class
   multiplicities for the already-restored guard, and fixes the launch plan and
   repeatable dry-run preview before any mutation.
2. Build saved PID groups in window order and dispatch every missing group
   immediately, without waiting for an earlier application to start. Then poll
   all outstanding rows together every 50 ms within one shared deadline
   (`restore_timeout_seconds`, default 20), placing each window as soon as it is
   matched. If one launch does
   not recreate every saved window, retry that group independently after a
   short grace period, up to the number of windows initially missing from the
   group.
   - Chromium app-mode windows reconstruct their URL from strict class metadata
     validated against either the initial title or saved `--app` argument and
     launch each through `omarchy-launch-webapp`, because the base Chromium
     process does not reopen those windows after reboot. Chromium's `Default`
     and `Profile_N` class suffixes are treated as the same web-app identity.
   - Launch through `hl.dsp.exec_cmd` with the saved silent workspace and
     floating rules.
   - Discover windows by polling and matching class, initial class/title,
     title, and workspace one-to-one.
    - Before applying the first window's state on each workspace, move the
      workspace to its resolved monitor. Prefer a connected monitor whose name
      and saved description agree, then a unique description match for renamed
       or rewired outputs. A disconnected output uses `monitor_fallback`: the
       focused monitor then lowest monitor ID by default, the lowest monitor
       directly, or a preferred connector. An unavailable preferred connector
       safely uses the default policy. Conflicting saved identities are skipped
       rather than guessed.
     - Apply state through the Hyprland Lua dispatcher API. After an actual
       monitor remap, refresh the client state. Temporarily clear pinning and
       fullscreen when they would block or alter a mutation, move to the saved
       workspace, set floating state, resize before moving floating windows,
       then restore fullscreen and pinned state. Monitor remapping happens first
       so it cannot invalidate restored geometry or pinned state.
     - Skip any property whose live client already matches the snapshot, and
       apply the remaining dispatches for one window in a single `hyprctl eval`.
       One evaluation replaces one process per property and prevents another IPC
       request from interleaving with the sequential dispatches. It is not a
       transaction or a compositor frame guarantee. Every dispatch is still
       attempted and failures are counted, so one failed property cannot skip
       the rest of the placement.
     - After placement and tiled correction, wait one polling interval and
       verify each matched floating window's compositor goal geometry within 2
       logical pixels. Reapply mismatched floating placements once, wait one
       more interval, and fail restore if geometry still differs. IPC loss during
       either verification remains retryable.
     - The production adapter suppresses `animations:enabled` for the mutation
       lifetime and puts the previous value back afterwards, including when
       placement raises. Hyprland otherwise animates every move, resize, and
       workspace change — the default Omarchy `windows` animation runs ~380 ms
       — so a restored desktop visibly shuffles itself into place after its
       windows have already mapped. Suppression is best-effort: an unreadable or
       already-disabled option leaves the setting untouched and restore
       proceeds unchanged. A process killed mid-restore cannot run its revert;
       `hyprctl reload` recovers.
     - After discovery, infer a binary guillotine split tree from each saved
       workspace's tiled rectangles. Exact replay, including two-window ratios,
       requires schema-v5 metadata,
      the saved and current dwindle layout, `use_active_for_splits` and
      `preserve_split`, disabled `permanent_direction_override`, complete
      bidirectionally unique matching, no unrelated or currently grouped tiled
      occupants, unchanged logical work-area dimensions, no saved
      groups/fullscreen/pinned members, no workspace-specific rules, at most 16
      leaves, and exactly one recursive decomposition.
    - Keep one seed leaf on the target workspace so its monitor assignment and
      lifetime remain stable. In one Lua evaluation, move the other leaves to a
      collision-resistant named staging workspace, focus each insertion leaf,
      preselect right or down, reinsert the corresponding child, set its
      immediate parent ratio, and restore the previously focused window or empty
      workspace. Every mutation dispatch result is asserted; final focus is
      separately restored and verified, including active special workspaces.
      Query clients afterward and require every work-area-relative rectangle to
      match within rounding tolerance. Recover staged leaves to the target
      workspace after a failed mutation; IPC loss remains retryable.
    - For eligible two-window dwindle workspaces, focus the known split, apply
      its exact saved ratio, restore the prior focus in the same Lua evaluation,
      and verify both resulting rectangles. Legacy or non-dwindle snapshots
      retain guarded absolute sizing. A compositor-accepted operation that does
      not settle to the saved geometry fails restore instead of silently leaving
      the default 50/50 split. Exact compatible-slot swaps remain available, and
      a monitor-origin change alone does not prevent either path.
3. Execute a prepared Restore run at most once. Rebuild or correct a tiled
   layout as soon as all of that workspace's saved
   windows are matched, without waiting for unrelated applications. Keep the
   final all-workspace pass after ordinary placement completes. Equivalent but
   geometrically ambiguous trees, master and
   other layouts, changed workspace dimensions, incomplete snapshots, and
   grouped tiled leaves retain fallback behavior. If a missing display falls
   back to a monitor with different dimensions, saved floating coordinates may
   not fit and remain best-effort.
4. On Hyprland 0.56+, re-form each complete, uniquely matched saved group after
   tiled correction. Require every member to be currently ungrouped, create the
   group through the public Lua API, append members in saved order, select the
   first saved member, and verify the ordered address list from a fresh clients
   query. Skip partial or ambiguous groups, unrelated current groups,
   inconsistent placement, and groups containing fullscreen or pinned windows.
   Hyprland 0.55 keeps ordinary window restoration and skips group formation.
   IPC loss is retryable; a requested mutation or verification failure is an
   application failure.

Restore failures return nonzero. Unavailable Snapshot history storage, capture,
focus, placement, monitor refresh/movement, replay, lock, critical
restore-complete marker persistence, or other IPC conditions are transient and
translate to exit 75 where systemd may retry. Current-session metadata failures
are only logged. Rejected actions, corrupt or inaccessible permanent storage
errors, and other permanent restore failures translate to exit 1, which prevents
a restart loop.
The adapters preserve this distinction as typed observation and mutation
results rather than inferring it again in commands. Log
details to `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/log/omarchy-sesh.log`,
but never include application launch commands or dispatcher output that may
echo them. Dry-run restore is an explicit diagnostic and prints launch commands
to its calling terminal.

## 6. Omarchy integration points

All confirmed against the installed Omarchy defaults.

1. **Startup** — `omarchy-sesh.service` is the only restore trigger. Older
   installer-owned Hyprland autostart lines are removed during upgrade. An
   advisory lock still protects manual concurrent invocations.

2. **systemd user service** — mirror Omarchy's shipped unit pattern
   (`/usr/share/omarchy/default/systemd/user/omarchy-crash-watch.service`,
   enabled via `install/user/first-run/enable-user-units.sh`):
   ```ini
   [Unit]
   Description=Omarchy session restore
    PartOf=graphical-session.target

   [Service]
   Type=oneshot
   UMask=0077
    ExecStart=%h/.local/bin/omarchy-sesh restore
    ExecStop=-%h/.local/bin/omarchy-sesh save --label logout --teardown
    RemainAfterExit=yes
    Restart=on-failure
    RestartPreventExitStatus=1 2
    RestartSec=2

   [Install]
   WantedBy=graphical-session.target
   ```
   `ExecStop` is diagnostic because graphical teardown may already have removed
   clients. It cannot replace the newest complete snapshot.

3. **Power-menu / logout wiring** — marker-delimited user menu overrides save
   synchronously, then invoke `omarchy-system-logout`, `omarchy-system-reboot`,
   or `omarchy-system-shutdown`. The save closes the current compositor's
   autosave gate while holding the operation lock and before querying Hyprland;
   periodic saves recheck that gate after acquiring the same lock. This ordering
   prevents a timer firing during teardown from superseding the power snapshot.
   Direct power commands bypass these overrides and rely on the latest periodic
   snapshot.

4. **Hook mechanism** — Omarchy has no pre-logout hook. Do not add another
   startup hook because that recreates the duplicate-restore race.

5. **Configuration** — `${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/sesh/config.json`
   supports `exclude_classes` (defaults skip polkit/portal agents),
   `autosave_seconds` (default 60), `restore_timeout_seconds` (default 20),
   `snapshot_retention` (default 5 per complete/diagnostic status class), and
   `monitor_fallback` (`focused` by default, `lowest`, or a connector-shaped
   name; any other string is rejected). The restore timeout must be at least
   `RESTORE_RETRY_DELAY` so a launch group can retry at least once. The file is
   read as UTF-8 regardless of the ambient locale.

   Only `save`, `restore`, and `autosave` load the file, and the complete object
   is validated before one of those operations acquires its lock.
   Malformed JSON, unknown keys, invalid types, and unsafe values fail `restore`
   closed: status 2, nothing restored, and `omarchy-sesh.service` does not
   restart on status 2, so a persistent configuration error cannot create a
   service loop. The capture path deliberately does not fail closed — `save` and
   `autosave` log the same error and continue with the defaults, because the
   power-menu and `ExecStop` callers discard the exit status, so aborting there
   would silently lose the session the tool exists to protect. For the same
   reason the autosave daemon keeps its normal `Restart=on-failure` and never
   exits on a configuration error. An unreadable file (an I/O or permission
   error rather than bad content) is transient and never fails one of those
   operations: it is logged and the command continues with the defaults.
   `status`, `list`, `delete`, `mode`, and `acceptance` do not load the file.

6. **Panel session state** — `omarchy-sesh mode --json` emits the autosave mode
   and best-effort current named-session label. A successful named save or
   restore attempts to write the current-session marker atomically; an ordinary
   manual save or automatic restore attempts to clear the name, while periodic
   saves preserve it. Deleting the current named session attempts to clear it.
   Failures are logged without changing the primary operation's result. The
   panel uses this interface to show `auto`, `manual`, a name, or `unavailable`
   when mode cannot be determined, and provides keyboard-accessible play/delete
   controls on its flipped session-list face.

## 6a. Prototype status (verified live on Hyprland 0.56.2)

`bin/omarchy-sesh` — python3, stdlib only (sqlite3, json, shlex). Subcommands:

- `save [--label X] [--name NAME]` — snapshots mapped clients + `/proc/<pid>` cmdline/cwd
  into `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/session.db` (WAL,
  status-aware snapshots).
- `restore [--name NAME] [--dry-run]` — loads the latest complete or requested
  named session, matches existing
  windows one-to-one, launches each saved PID group with bounded retries for
  missing windows, and places every matched window. Lua arguments use
  collision-free long strings.
- `autosave [--interval N]` — periodic save loop (crash cover). It refreshes
  the current Hyprland instance from the systemd user manager before each
  capture so a startup restore retry cannot leave it on a stale compositor, and
  rechecks the completion gate under the operation lock. Failed restore and
  synchronous shutdown markers keep autosave gated until restore succeeds or
  the user explicitly establishes a new baseline through manual/Active mode.
- `status` — lists recent sessions.
- `list [--json]` — lists retained named sessions, optionally as JSON.
- `delete --name NAME` — removes a named session and its captured state.
- `mode [active|manual] [--json]` — queries or changes autosave mode; JSON also
  reports the current named session.
- `acceptance [--expect-power-save|--expect-restore-failure]` — reports evidence
  for a deliberate live acceptance run without performing a live save, restore,
  mode change, or power action. CLI startup can still maintain owner-only state
  and migrate legacy XDG state.

Verified end-to-end: save → close app → `restore` relaunched Nautilus and
placed it at the exact saved `at [145,75] size [1000,700]` floating. Test
windows were cleaned up after each run.

`systemd/user/omarchy-sesh.service` is the single restore trigger and retries
temporary lock or IPC failures. Application launch/placement failures are not
automatically relaunched in a loop. Autosave waits one interval and remains
gated while startup restore is retryable. Saves retain the configured number of
complete and diagnostic snapshots independently (five of each by default).

Window group membership and order are implemented for Hyprland 0.56+, pending
controlled live acceptance. Active-tab and lock/deny state are not restored
because clients JSON does not expose reliable saved values. `stableId` matching
was investigated and rejected because the value does not survive window
recreation or a Hyprland restart.

Schema-v5 nested dwindle replay is implemented with pure geometry inference,
staged public-dispatch reconstruction, focus restoration, and final rectangle
verification. Controlled reboot acceptance remains pending; legacy snapshots
use the existing tiled fallback until a new capture stores workspace metadata.
The database user version remains 6; Snapshot history migrates every supported
existing database in place and this architecture release adds no dependencies.

## 7. Decisions And Open Questions

- **Language:** bash + `sqlite3` CLI (matches Omarchy script style) vs a
  single python3 script with stdlib `sqlite3`/`json` (cleaner JSON + SQL,
  still zero deps). Recommend python3 for parse robustness; bash wrapper for
  the omarchy-* command surface.
- **`stableId`:** Hyprland clients expose `stableId`, but upstream commit
  [`68456a5`](https://github.com/hyprwm/Hyprland/commit/68456a5d9a54f34b70a8261153dc7d35c17f2bf0)
  generates it from a process-static counter for each new Wayland or XWayland
  window object. It changes on window recreation and the counter resets with
  Hyprland, so it is useful only as a live selector and must not outrank
  class/title matching for reboot restoration.
- **Manual vs automatic restore:** default restore on every login, with a
  "don't restore" toggle (`${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/…`, matching
  omarchy-crash-watch's toggle pattern).
- **Groups (tab groups):** membership and order are restored only for complete,
  uniquely identified groups. Active-tab and lock/deny capture remain open only
  if Hyprland exposes stable public state for them.

## 8. Verification plan

1. `omarchy-sesh save` → `sqlite3 session.db 'select * from windows'` shows
   correct classes/geometry/cmdline.
2. Launch a test set: a floating window (e.g. a scratchpad terminal), a tiled
   terminal in a tmux session, a browser, a fullscreen/pinned window; reboot.
3. After login, confirm: apps relaunch, floating windows land at saved
   `at`/`size`, tiled windows land on saved workspaces in order, browser
   restores its own tabs.
4. Crash test: `kill -9` a window, `sleep 60`, reboot — periodic snapshot
   still restores.
5. No-window test: fresh session with no snapshot → restore no-ops.

Automated coverage uses temporary SQLite files for Snapshot history and the
deterministic adapter for Restore run scenarios. Scenarios queue observation and
action results, model launch appearances and tiled replay, and assert event
ordering and deterministic time. Focused matching, geometry, Lua encoding, and
production translation tests remain at their narrower seams. Source-contract
tests cover panel/CLI integration without claiming live QML verification, and a
schema-v6 upgrade fixture verifies in-place migration through Snapshot history.
