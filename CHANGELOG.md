# Changelog

All notable changes to `omarchy-sesh` are documented here.

## Unreleased

## v0.2.8 - 2026-09-02

### Added

- The panel now flips to the named-session list and gives each row separate play
  and delete controls. Deletion requires confirmation and supports pointer,
  Enter, Escape, Left/Right, Tab, and `x` keyboard behavior.
- The panel header now shows `auto`, `manual`, or the current named session.
  `omarchy-sesh mode --json` reports both fields for panel consumers.
- An owner-only
  `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current-session.json` marker
  provides best-effort current named-session metadata for the panel. Named saves
  and restores attempt to set it; ordinary manual saves and automatic restores
  attempt to clear it, periodic saves preserve it, and deletion of the current
  name attempts to clear it. Write failures are logged without failing an
  otherwise successful save, restore, or delete.

### Changed

- Snapshot history is now a deep module that owns schema migration,
  transactions, selection, retention, naming/deletion, and storage error
  classification behind one interface. It returns immutable Snapshots, and
  each immutable Snapshot window uses snapshot-local order as identity instead
  of exposing a SQLite row identity.
- Restore run now prepares one immutable plan with a repeatable, effect-free
  preview and single-use execution. The module retains the shared deadline,
  concurrent launches, matching, placement/correction order, and typed outcome;
  commands retain locks, markers, output, and exit translation.
- `ProductionHyprland` and `DeterministicHyprland` now implement the same
  semantic capture, observation, action, and result interface. Lua generation,
  selectors, command redaction, monitor refresh, and animation lifetime remain
  local to the production adapter, improving locality while keeping the module
  seam narrow.
- Restore tests now use deterministic compositor state, queued action results,
  replay modeling, event ordering, deterministic time, and temporary SQLite
  histories. Focused matching, geometry, and encoding tests remain at their
  narrower seams, preserving depth and test leverage without weakening coverage.
- Automated coverage now includes the panel/CLI source contracts and an
  in-place schema-v6 upgrade fixture. Live QML acceptance remains outstanding.

### Fixed

- Transient capture, Snapshot history storage, focus, placement, monitor, and
  tiled-replay failures retain retryable typed outcomes and translate to exit
  75 where systemd may retry. Rejected mutations and permanent storage or
  restore failures translate to exit 1 and do not create a restart loop.
- Installation now creates the current-session marker owner-only, upgrades
  repair its permissions, and uninstall removes it. Operation-time updates
  remain best-effort secondary metadata.
- The panel now reports an unknown autosave mode as `unavailable` rather than
  presenting it as Manual mode.

### Compatibility

- The SQLite schema remains version 6 and existing databases migrate in place.
  This release adds no dependencies and retains the existing CLI lock, marker,
  output, restore ordering, and exit-status contracts.

## v0.2.7 - 2026-08-26

### Changed

- The Restore run module now owns live observation, one-to-one matching, launch
  scheduling, placement, tiled correction, group reconstruction, verification,
  animation lifetime, and outcome construction. The command retains Snapshot
  selection, dry-run rendering, restore-marker persistence, output, and exit
  translation.
- Selected Snapshots are copied into immutable values and restore settings are
  validated at the module interface, preventing observation-to-execution state
  from changing during a prepared Restore run.
- Hyprland operations, monotonic time, sleeping, and logging now cross explicit
  internal seams. Post-selection scenarios exercise the Restore run interface
  with deterministic in-memory adapters instead of invoking private
  orchestration or patching global time and compositor functions.
- Restore ordering coverage now proves live observation precedes the incomplete
  marker, animation suppression, desktop mutation, animation restoration, and
  the final completion marker.

### Compatibility

- Restore behavior, CLI output, exit semantics, and the SQLite schema are
  unchanged. Completed automatic restores still require live compositor IPC
  before fast-skipping without loading Snapshot payload data.

### Fixed

- The README now correctly states that fresh installs enable Active autosave by
  default; upgrades still preserve an existing Manual selection.

## v0.2.6 - 2026-08-24

### Changed

- Restore orchestration now runs through a dedicated restore-run module with a
  named outcome for restored windows, launched processes, permanent failures,
  and retryable transport failures. Existing restore behavior and exit semantics
  are unchanged.
- Restore lifecycle tests can use an in-memory compositor adapter, while the
  production adapter retains Hyprland animation suppression around the complete
  restore run.

## v0.2.5 - 2026-08-21

### Fixed

- Two-window dwindle workspaces now use the same guarded, gap-aware exact tree
  replay as nested layouts, preserving saved splits such as 30/70 instead of
  accepting Hyprland's default 50/50 split.
- Tiled ratio correction now verifies the resulting compositor geometry and
  restores focus after incremental replay; a compositor mutation that has no
  effect is reported as a restore failure instead of silent success.

### Compatibility

- This release does not change the SQLite schema or require a migration. It
  reuses the existing `windows` geometry and `workspace_layouts` metadata.

## v0.2.4 - 2026-08-21

### Security

- Runtime state directories and files are now owner-only, existing permissive
  installations are repaired during CLI use and upgrades, and application
  launch commands are redacted from restore failure logs.

### Fixed

- Floating restore now temporarily clears blocking pinned and fullscreen state,
  refreshes client data after monitor remapping, and verifies final geometry
  with one retry after the compositor settles.

## v0.2.3 - 2026-08-20

### Changed

- The panel re-checks installation on every open and reinstalls from the
  checkout when anything is out of date, so the installed `omarchy-sesh` binary
  stays in sync with the project's `bin/omarchy-sesh` even between version
  bumps. The freshness check now compares the checked-out binary against the
  installed one with `cmp` in addition to the version marker, units, service,
  and mode checks.
- Removed the first-open special case in the panel; installation and mode
  refresh share a single open path.

## v0.2.2 - 2026-08-20

### Added

- The panel's Restore action now opens a keyboard- and pointer-accessible picker
  of named sessions, displaying each name, capture time, and window count.
- `omarchy-sesh list --json` emits named-session metadata for panel consumers.

### Fixed

- Named sessions can now be restored repeatedly in the same Hyprland desktop;
  the one-per-desktop guard remains in place for automatic latest restore.

## v0.2.1 - 2026-08-20

### Added

- Named session snapshots: `save --name NAME`, `restore --name NAME`, `list`,
  and `delete --name NAME`. Names are conflict-safe, retained independently of
  automatic snapshots, and schema version 6 migrates existing databases.
- Named saves confirm success with `Session saved under NAME`; failed captures
  now report unavailable Hyprland IPC directly to the invoking user.
- Monitor-aware restoration records connector names and physical display
  descriptions, resolves renamed or rewired outputs, and uses a deterministic
  fallback for disconnected displays.
- Workspace-to-monitor remapping runs before window state and tiled layout
  restoration.
- Best-effort tiled layout correction restores simple two-window split ratios
  and swaps uniquely identified windows into compatible saved slots.
- Database schema version 3 migrates existing snapshots to include monitor
  descriptions.
- Database schema version 4 migrates existing snapshots to store nullable,
  snapshot-local window group membership and order.
- Database schema version 5 stores complete workspace layout type and bounds for
  guarded nested tiled replay; legacy snapshots continue using the fallback.
- Complete, uniquely matched and unambiguous nested dwindle layouts are rebuilt
  through staged public Lua dispatches and verified against saved rectangles.
- Hyprland 0.56+ restores complete, uniquely matched window groups in saved
  order after placement while preserving unrelated current groups.
- Regression coverage now includes monitor identity conflicts and fallbacks,
  tiled split sizing and slot correction, Chromium profiles, global matching,
  restore markers, XDG paths, and installer recovery.
- Validated configuration now controls restore timeout, per-status snapshot
  retention, and disconnected-monitor fallback alongside the existing exclude
  and autosave settings.

### Changed

- Malformed or unknown configuration fails restore closed before any side
  effects, and `omarchy-sesh.service` does not restart-loop on it. Save and
  autosave instead log the error and continue with the defaults, so a
  configuration typo cannot skip a logout snapshot or stop periodic saves.
- `omarchy-sesh mode` warns when autosave is enabled but not running.
- Window discovery uses ranked one-to-one assignment instead of greedy class
  matching, reducing incorrect matches between similar windows.
- Hyprland 0.55 remains supported and restores grouped windows independently;
  direct group reconstruction is capability-gated to 0.56 or newer.
- Restore dispatches all initially missing process groups before polling and
  places fast windows without waiting for slower applications.
- Restore suppresses Hyprland animations through the Lua configuration API
  while it places windows and puts the previous setting back afterwards, so a
  restored desktop no longer visibly shuffles itself into position after its
  windows have mapped.
- Each window's placement is applied in one Hyprland Lua evaluation instead of
  one `hyprctl` process per property, cutting a floating window's placement
  cost from about 33 ms to about 8 ms and landing every property inside a
  single compositor frame.
- Placement skips workspace, float, fullscreen, and pin dispatches whose live
  window already matches the snapshot.
- Chromium app-mode identity validation accepts supported profile suffix
  changes while rejecting unrelated or malformed classes and URLs.
- Ordinary Chromium relaunches strip shared app-mode arguments to avoid
  duplicate web-app windows.
- The panel reports unknown mode and incomplete installations more accurately
  and only initiates installation through an explicit user action.
- Installer updates preserve Manual mode, restart autosave only when it was
  already active, and retain user-owned power actions.

### Fixed

- Nautilus restore strips its internal `--gapplication-service` flag so the
  relaunched process opens a file-manager window instead of service mode only.
- Incomplete or failed restores now keep autosave gated so they cannot replace
  the latest complete snapshot.
- Restore-complete marker writes are atomic, their failures are retryable, and
  dry runs no longer alter restore state.
- Existing restore markers no longer bypass live compositor IPC checks.
- Autosave refreshes the Hyprland instance before every capture and clears
  stale compositor environment values.
- Synchronous power-action saves close the autosave gate under the operation
  lock so a periodic capture cannot supersede them during graphical teardown.
- Empty XDG environment variables no longer create relative state paths, and
  state accidentally written to those paths is migrated.
- Uninstall removes legacy and dangling artifacts and stops safely when service
  state cannot be verified.
- Tiled restore skips incomplete, ambiguous, differently oriented, differently
  bounded, or unsupported layouts instead of modifying an uncertain split tree,
  and recovers staged windows if nested replay verification fails.

## 0.1.0 (alpha) - 2026-08-17

### Added

- Dependency-free Python CLI with `save`, `restore`, `autosave`, `status`, and
  `mode` commands.
- SQLite session storage with in-place migrations, WAL mode, status-aware
  snapshots, and retention of five complete and five diagnostic captures.
- Capture of mapped Hyprland windows, launch commands, working directories,
  workspaces, geometry, and floating, fullscreen, pinned, and XWayland state.
- One-to-one existing-window matching and saved-PID launch grouping, including
  bounded retries for multi-window processes.
- Concurrent application launch with one shared restore deadline and
  collision-safe Lua dispatch arguments.
- Pixel-exact floating resize and placement, saved workspace assignment, and
  fullscreen and pinned state restoration.
- Strict Chromium web-app relaunch through `omarchy-launch-webapp`.
- Complete empty snapshots as authoritative restore sources while partial,
  failed, teardown, and ambiguous legacy captures remain diagnostic.
- Autosave crash cover that waits one interval and remains gated until startup
  restore succeeds for the current compositor instance.
- Active and Manual mode control, including baseline capture before enabling
  autosave when no successful restore marker exists.
- Advisory locking for save and restore operations and distinct retryable versus
  application-failure exit semantics.
- A single systemd startup restore service and an autosave service ordered after
  it.
- Omarchy bar widget with Active, Manual save, and Restore actions, status icon,
  keyboard and mouse controls, and asynchronous CLI orchestration.
- Idempotent user-level installation, upgrade repair, and symmetric uninstall.
- Marker-delimited power-menu actions that save synchronously before logout,
  reboot, or shutdown without replacing existing user actions.
- Optional `exclude_classes` and `autosave_seconds` configuration through XDG
  paths.
- Dry-run restore planning and state-file logging.

### Fixed

- Startup restore no longer competes with a duplicate Hyprland autostart hook.
- Teardown and failed captures cannot supersede the newest healthy snapshot.
- Reinstalling the plugin preserves Manual mode instead of silently enabling
  autosave.
