# Clip History Architecture Review Notes

## 2026-04-29 Partial User Review

### 1. Pseudo-Clip Override

User approved the proposed transient per-track pseudo-clip override.

Decision so far:

- audition is runtime state;
- audition must not mutate document truth;
- the override is cleared when the modal closes;
- save is the moment the pseudo clip becomes a real clip.

### 2. History Window And Storage Shape

User confirmed 16 bars is fine.

User asked whether the history could be compressed like MIDI events when cells are empty.

Architecture interpretation:

- the UI needs a step-addressed 16-bar view so empty cells remain visible and selectable;
- the runtime buffer does not need to be a dense persisted clip;
- a sparse/event-like representation is acceptable internally as long as it can materialize a deterministic step window for audition/save;
- a ring of step buckets is also acceptable if cheap, because empty buckets over 16 bars are still small;
- dense `ClipContent` should be created only when needed for pseudo-clip audition or final save.

Remaining architecture review questions:

- occupied pattern-slot overwrite behavior;
- history-region UI behavior.
