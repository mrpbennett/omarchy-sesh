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
