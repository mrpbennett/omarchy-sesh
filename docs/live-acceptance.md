# Live Acceptance

This procedure completes the live validation work tracked in
`docs/future-improvements.md`. Run it only in an intentional Omarchy/Hyprland
test session: the reboot, power-menu, and failed-launch cases affect the current
desktop. The evidence command performs no live save, restore, mode change, or
power action. It is not strictly read-only because normal CLI startup may create
or repair owner-only runtime state and migrate legacy XDG state.

## Reboot Restore And Service Health

1. Open a tiled terminal, a floating terminal with a distinctive size and
   position, a browser, and a multi-window application. Put them on at least two
   workspaces. Include a complete window group when testing Hyprland 0.56+.
2. Record each application's workspace. Record the floating window's `at` and
   `size` from `hyprctl -j clients` before reboot. For a nested dwindle layout,
   record all tiled rectangles as well.
3. Use the Omarchy **Reboot** power-menu action. Do not use a direct reboot
   command; this exercises the synchronous pre-shutdown snapshot.
4. After login and after applications settle, run:

   ```sh
   omarchy-sesh acceptance --expect-power-save
   ```

5. Confirm every line reports `PASS`. The command verifies the current
   compositor marker, source snapshot, restore service, autosave state, and
   one-to-one saved-window matching. `--expect-power-save` additionally proves
   that the restored source snapshot has the `logout` label.
6. Compare the recorded workspace and floating geometry with `hyprctl -j
   clients`. Confirm browser content using the browser's own restore behavior.
   For a complete nested dwindle layout, compare every recorded tiled rectangle
   and group member order. Tiled layout remains best-effort when its documented
   replay prerequisites are not met.

## Failure Recovery

Use an application launcher that can be made unavailable after its window has
been saved, without changing the saved database. Capture a normal desktop with
that application open through the Omarchy power menu, make its launcher exit
without creating a window, then reboot through the same menu.

After login, run:

```sh
omarchy-sesh acceptance --expect-restore-failure
```

The command expects the restore unit to be failed, the completed-attempt marker
to permit autosave, the autosave service to remain active when enabled, and the
restore source to remain a complete snapshot. Separately inspect
`${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/restore-complete.json` and confirm
its `instance` equals the current `HYPRLAND_INSTANCE_SIGNATURE`. Restore the
test application's launcher before the next normal reboot.

This is the permanent-failure case: confirm the restore command exits 1 and the
unit does not restart-loop. In a separate controlled run, make one Hyprland
observation or action temporarily unavailable without changing the Snapshot.
Confirm the command exits 75, systemd retries, and a later attempt succeeds once
IPC is available. An incomplete launch also keeps autosave gated and records a
30-second observation grace before startup relaunches missing rows. Exercise
capture, monitor movement/refresh, placement, focus,
and tiled replay separately when practical. A transient startup Restore run
must leave autosave gated until a retry succeeds.

## Panel Session Controls

1. Open the panel, select **Manual**, and confirm the header shows `manual`.
   Active mode always displays `auto`, not a current named session.
2. Create two named sessions with `omarchy-sesh save --name NAME`, then reopen
   the panel and confirm its header shows the most recently saved name.
3. Choose **Restore** and confirm the panel flips to a list containing both
   names, capture times, window counts, play controls, and delete controls.
4. Restore one row by pointer and one by keyboard selection plus Enter. After a
   successful restore, reopen the panel and confirm its header shows that name.
5. Start deletion with the row control and with `x`. Confirm Cancel is selected
   initially; Left/Right and Tab switch buttons, Enter answers, and Escape
   cancels without restoring the row underneath.
6. Confirm deletion, verify the list reloads without that name, and verify the
   current-session label clears when the deleted name was current. Escape and
   the back arrow must return from the list to the three primary actions.
7. If the mode query reports neither Active nor Manual, confirm the panel shows
   `unavailable` rather than presenting the state as Manual.

Retain command output and screenshots for these checks. They do not complete the
plugin acceptance roadmap item until exercised in a live Omarchy shell.

## Evidence To Retain

Record the command output, `systemctl --user status omarchy-sesh.service
omarchy-sesh-autosave.service`, and the pre/post `hyprctl -j clients` captures.
For monitor remapping or group testing, add monitor and group metadata to those
captures. Do not mark a roadmap item complete until the visual assertions and
the command evidence both pass.
