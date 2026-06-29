# AU instrument loading: preset doesn't change the sound (esp. during playback) + a note hangs

**Filed:** 2026-06-29 (owner, verifying the AU preset-picker fix)
**Area:** AU instrument host — preset apply + note scheduling
  (`Sources/Audio/AudioInstrumentHost.swift`)
**Severity:** FUNCTIONAL — core AU-instrument loading is unreliable
**Status:** PARTIAL — hung-note path addressed in code; acoustic A/B still owed (2026-06-29)

## Progress (2026-06-29)

**Hung note (symptom 2) — code fix landed.** `AudioInstrumentHost.loadPreset`
now sends a sample-stamped **All-Notes-Off (CC 123)** through the AU's OWN
`scheduleMIDIEventBlock` immediately after `au.currentPreset = preset` (inside
`auMutationLock`, before the ProgramChange-quirk block). This clears a note left
ringing by the patch reconfiguration deterministically — ordered on-thread right
after the switch, unlike the pre-existing async main-hop `stopNote` panic which
races the reconfiguration. RT-safe (the block copies bytes synchronously; same
path as the program-change code) and lint-clean (uses the sanctioned stamped
path, not `stopNote`/`startNote`). New helper `allNotesOffBytes()` +
unit test `test_allNotesOffBytes_is_CC123_value_0_on_channel_0`.

**Still OPEN — needs a human-present real-AU session (cannot verify by code/ears
here):**
- Symptom 1a (**brief transport pause** on switch): most likely the AU's own
  synchronous patch reload blocking render (AU-internal) and/or the heavy
  `captureState`/`fullState` read on main under the lock — not fixed.
- Symptom 1b (**old sound persists** on general, non-`ProgramChangeN` AUs):
  `au.currentPreset =` is the standard API and is left as-is; the documented
  `TODO(u5)` wait-for-parameter-tree-change was NOT implemented (complex +
  unverifiable offline). NOTE: part of the "old sound" perception may have been
  the hung note above (the old patch's note ringing through) — re-test 1b AFTER
  confirming the hung-note fix.

**Acceptance still requires** the owner's STOPPED-vs-PLAYING real-AU A/B per the
isolation questions below.

The AU-instrument path (load an AU on a track, pick presets, play) does not work
reliably. This is the real issue behind the AU verification items.

## Symptoms (owner, real AU)

1. **Selecting a preset does not change the sound** — and during playback it is
   clearly broken:
   - Switching preset *while playing* caused a **brief pause where playback
     stopped**, then **resumed playing the OLD sound**. So the preset apply both
     (a) glitched/stalled the transport and (b) did not switch the patch.
2. **A note hangs / is held too long** — "perhaps to the end of the bar." Points
   at the AU note-OFF not being scheduled, or scheduled far in the future.

## Strongest clue (no logging needed)

The "**brief pause, then old sound**" on preset change is diagnostic on its own:
- The **pause** means `loadPreset` is doing heavy/blocking work on a path that
  stalls audio — candidate: `au.currentPreset =` and/or the follow-on capture +
  commit (`captureState` → `writeStateBlob` → `.auState` scoped runtime) running
  in a way that disrupts the running engine/render.
- The **old sound after** means `au.currentPreset =` did not actually switch this
  AU's patch (the original 20260624-165547 bug), and the earlier narrow fix
  (`ed12360a`) did not apply — it only sends a MIDI Program Change for presets
  named literally `ProgramChangeN`, which this AU's presets are not. So the
  general case (currentPreset ignored, esp. mid-render) is still unsolved.

## Code areas to investigate (`Sources/Audio/AudioInstrumentHost.swift`)

- **`loadPreset`**: `au.currentPreset = preset` then `factory.captureState`. Why
  does it pause playback? Is the capture/commit reconfiguring or briefly stalling
  the engine? Does `currentPreset =` need the AU re-prepared / a parameter-tree
  wait (there's a `TODO(u5)` about exactly this) to take effect during rendering?
- **Note off / hung note**: `noteStamps` computes
  `noteOff = noteOn + max(1, gateFrames)` where
  `gateFrames = secondsPerStep × length × sampleRate`. A wrong/large `length`
  (gate steps) for AU notes, or the past-frame clamp sending BOTH stamps to
  `AUEventSampleTimeImmediate`, would explain a stuck note. Also the documented
  same-pitch-overlap limitation on channel 0 (`scheduleNote` comment).

## Isolation questions
- Does `currentPreset =` switch the sound when playback is STOPPED (vs running)?
- Does the hung note happen with the AU WITHOUT touching presets? (separates the
  note path from the preset path)
- Which AU + preset names (confirms the ProgramChange gate is irrelevant here)?

## Note on instrumentation
A live `DevActivity`/`SequencerTimingProbe` capture was attempted but produced no
`log show`/`log stream` output for the running app this session (separate
observability friction — NOT this bug). Investigate from code + a STOPPED-vs-
PLAYING manual A/B first; if instrumentation is needed, see the corrected enable
steps in `wiki/pages/runtime-observability.md` (sandbox container default + env
via direct binary launch) before relying on it.

## Acceptance
- Selecting an AU preset changes the sound, including during playback, with no
  transport pause/glitch, for general AUs (not only `ProgramChangeN`).
- AU notes have correct gate length — no hang.
