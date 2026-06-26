# Bug: a track can be muted AND soloed at the same time

**Filed:** 2026-06-26 — Max, real-audio verification pass (#42). Fix later.
**Severity:** logic/UX — contradictory states.

## What happens
A single track can have BOTH mute and solo engaged at once. These are
contradictory and should be mutually exclusive (engaging one should clear/override
the other), per standard mixer behaviour.

## Expected (decide the exact rule when fixing)
Engaging solo on a muted track should un-mute it (or solo overrides mute for that
track); engaging mute on a soloed track should drop it from solo. At minimum the
two indicators must never both show active on the same track.

## Fix direction (later)
In the track mute/solo state model + the mixer toggle handlers, make mute and solo
mutually exclusive per track (or define a clear precedence). Ensure the resolved
effective-audibility (the OR-combine mute model, #54, + solo set) reflects the
chosen rule, and the UI indicators follow.
