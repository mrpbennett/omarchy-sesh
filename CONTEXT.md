# Omarchy Session Restoration

This context captures the terms used to preserve and restore a desktop session.
It keeps restore behavior distinct from application-owned state.

## Language

**Snapshot**:
A saved description of one desktop session, including its windows and saved
workspace layout, that may be selected for restoration.
_Avoid_: backup, session file

**Snapshot history**:
The ordered collection of retained Snapshots and the rules for recording,
selecting, naming, retaining, and deleting them.
_Avoid_: session database, snapshot store

**Restore run**:
A single attempt to apply one saved session to the current Hyprland desktop,
from matching existing windows through launch, placement, correction, and final
verification.
_Avoid_: restore process, restore flow

**Restored window**:
A saved window that has been matched or relaunched and returned to its saved
workspace, floating or tiled state, and geometry as far as the compositor
allows. Application-owned content and state are outside restoration.
_Avoid_: restored application, restored process

**Terminal window restoration**:
Recreation of each saved terminal window as a Restored window, including its
saved terminal emulator type and a working directory only when that directory
can be attributed safely. Each saved compositor window is recreated as one OS
window even when multiple windows previously shared a terminal server process.
Shell history, running commands, tabs, panes, and unsaved terminal state remain
terminal-owned.
_Avoid_: terminal session restoration

**Incomplete restore**:
A Restore run in which at least one saved window has not appeared by the shared
deadline. An Incomplete restore is distinct from a rejected operation and does
not prove that relaunching the same application is safe.
_Avoid_: failed restore, timed-out application

**Complete restore**:
A Restore run in which every saved window became a Restored window and all
required verification succeeded.
_Avoid_: successful process launch

**Degraded restore**:
A Restore run in which every saved window appeared, but a best-effort placement
or geometry property could not be verified. Degradation does not make the
Snapshot incomplete.
_Avoid_: partial restore

**Failed restore**:
A Restore run that cannot succeed unchanged because an operation was rejected,
a required application is unavailable, or persisted input is invalid.
_Avoid_: incomplete restore, degraded restore
