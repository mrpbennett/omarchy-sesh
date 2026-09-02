# Future Improvements

## Acceptance Testing

- [ ] **Reboot restore**: reboot with tiled, floating, browser, terminal, and
      multi-window applications open. Confirm each window returns to its saved
      workspace and floating geometry.
- [ ] **Service health**: after reboot, verify `omarchy-sesh.service` completes,
      autosave is active when enabled, and neither service enters a restart
      loop.
- [ ] **Omarchy plugin**: load the widget in the live shell, inspect both shield
      states, exercise Active, Manual, and the flipped Restore list, and verify
      the current-session label plus confirmed pointer and keyboard deletion.
      Automated source-contract coverage does not complete this live QML item.
- [ ] **Power menu**: confirm Omarchy logout, reboot, and shutdown actions save
      before Hyprland destroys its clients.
- [ ] **Failure recovery**: force one application launch to fail and confirm
      autosave does not replace the last complete Snapshot. Separately force a
      transient observation/action failure and confirm exit 75 permits retry,
      while a rejected permanent action exits 1 without a restart loop.

## Restore Quality

- [x] **Monitor remapping implementation**: save connector and display identity,
      resolve renamed or rewired outputs by description, and move workspaces to
      a deterministic fallback when their saved monitor is disconnected.
- [ ] **Monitor remapping acceptance**: verify saved workspaces on disconnected,
      renamed, rewired, and reordered monitors, including floating geometry on
      a differently sized fallback display.
- [x] **Stable identity investigation**: Hyprland `stableId` is a per-process
      incrementing window-object ID. It changes when an app creates a new window
      and its counter resets when Hyprland restarts, so it cannot identify a
      semantic window across reboot and is intentionally not persisted.
- [x] **Window group implementation**: capture complete membership and order,
      then safely reconstruct uniquely matched groups through Hyprland 0.56's
      public Lua API after placement.
- [ ] **Window group acceptance**: verify ordered reconstruction live, including
      partial, ambiguous, pre-existing, floating, and failed groups. Active-tab,
      fullscreen/pinned, and lock/deny restoration remain unsupported.
- [ ] **Exact tiled layout serialization**: pursue a Hyprland API or native
      plugin that exports and restores dwindle/master split trees and ratios.
      This is the robust replacement for inferred pixel resizing, but a local
       plugin would require C++ code tied to Hyprland's unstable internal ABI and
       rebuilding for matching compositor versions.
- [x] **Inferred nested dwindle replay**: infer an unambiguous guillotine tree
      from schema-v5 workspace geometry, rebuild complete uniquely matched
      workspaces through guarded public Lua dispatches, restore focus, and verify
      every final rectangle. Controlled reboot acceptance remains outstanding.
- [x] **Translated tiled sizing**: restore simple two-window split ratios when
      monitor reordering changes the workspace origin but not its dimensions.
- [ ] **Slow applications**: collect real startup timings and change the default
      restore timeout only if the current configurable 20-second bound is
      insufficient.
- [x] **Polling latency**: reduce window-discovery polling from 200 ms to 50 ms,
      limiting avoidable detection delay without changing restore semantics.
- [ ] **Restore performance benchmark**: benchmark dispatch and window-discovery
      latency with larger sessions. Python is currently appropriate because
      restore is I/O-bound, applications launch concurrently, and its standard
      library provides robust JSON, SQLite, process, and `/proc` handling
      without extra dependencies. A synthetic matching benchmark reached a
      7.62 ms p95 at 64 windows; live IPC and discovery timings remain. If
      subprocess polling remains a bottleneck,
      investigate Hyprland event notifications or persistent IPC before
      considering a language rewrite.
- [x] **Chromium app-mode launcher**: strictly recognized web-app windows launch
      individually through `omarchy-launch-webapp` when Chromium cannot recreate
      them through a bounded generic relaunch.
- [ ] **Additional launchers**: add more application-specific handling only for
      apps proven not to recreate their saved windows through bounded generic
      relaunches.

## Omarchy Integration

- [ ] **Plugin removal UX**: monitor Omarchy plugin lifecycle support. Replace
      the documented uninstall-before-remove sequence if official uninstall
      hooks become available.
- [ ] **Menu customization coverage**: test user menu files that customize
      power action labels, icons, conditions, or commands without overwriting
      user-owned behavior.
- [x] **Configuration surface**: expose validated settings for excludes,
      autosave interval, restore timeout, snapshot retention, and monitor
      fallback. Preserve existing defaults when extending configuration.
- [ ] **Upgrade coverage**: test plugin upgrades from each released schema and
      manifest version while preserving Manual mode and existing Snapshots.
      An automated schema-v6 upgrade fixture covers in-place migration through
      Snapshot history; the release-to-release matrix and owner-only
      current-session marker repair still require broader upgrade coverage.

## Release Readiness

- [x] Run the complete Python, Bash, systemd, and plugin validation suite.
- [ ] Perform one clean install, update, and uninstall in an isolated home.
- [ ] Document confirmed limitations and recovery commands in `README.md`.
- [ ] Remove generated artifacts and review the final release diff.

## Definition Of Done

An item is complete only when its behavior is covered by an automated test
where practical, verified on a live Omarchy/Hyprland session when integration
is involved, and documented without replacing existing Omarchy defaults.
