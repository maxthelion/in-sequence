---
title: "Architecture Guardrails"
category: "architecture"
tags: [architecture, guardrails, buffers, snapshots, document, runtime]
summary: Cross-cutting architecture decisions PM and implementation work should preserve.
last-modified-by: codex
---

This page records cross-cutting architecture choices that roadmap architecture passes should check before a feature becomes a spec.

It complements [[project-layout]], [[document-model]], [[engine-architecture]], and [[code-review-checklist]].

For product and runtime orientation, start with [[application-overview]], [[information-architecture-ux]], and [[playback-data-path]].

## Document Truth Versus Runtime State

The `.seqai` document is persisted user truth. It should contain authored musical state and references, not temporary UI/runtime state.

Runtime-only states should stay out of the document unless the user explicitly commits them. Examples:

- audition state;
- transient capture/history buffers;
- selected prototype or modal state;
- transport-derived state;
- cached playback snapshots.

If a feature has a "preview", "audition", "cue", or "pseudo" state, the architecture pass must say when, if ever, that state becomes persisted document data.

## Playback Snapshots And Buffers

Hot playback code should prefer compiled, typed runtime data over ad hoc traversal of the full document model.

Current examples:

- `PlaybackSnapshot` carries typed runtime fields and no longer embeds the whole `Project`.
- `ClipBuffer` stores clip steps and macro overrides in compact step-indexed arrays.
- `PhrasePlaybackBuffer` stores phrase state as arrays keyed by step.
- `SnapshotChange` records narrow invalidation domains so live mutations do not default to full rebuilds.

When a feature affects playback, the architecture pass should ask:

- does this belong in persisted document state, a compiled snapshot, or transient runtime state?
- can the hot path read a small buffer or lookup rather than walking the document?
- what narrow invalidation should update the compiled runtime state?
- what tests prove the runtime buffer matches the authored document truth?

The current canonical note-resolution path is documented in
[[playback-data-path]]. The generated ownership diagrams live in
`docs/diagrams/`, with editable D2 sources in `docs/diagrams/src/` and the
review vocabulary in `docs/architecture/runtime-ownership-manifest.yml`.

## Performance-Time Mutation Rule

Treat user actions differently depending on how often they can happen during
playback.

Structural edits may use a broad document-model path when the user performs
them occasionally:

- add or delete a track, bus, route, or scene;
- change a destination that rebuilds an AU/MIDI output shape;
- commit a captured/recorded object into the document.

Performance-time controls must not depend on wholesale `Project`
export/import, `EngineController.apply(documentModel:)`, or broad sync on every
gesture tick. Examples include:

- fader, pan, mute, solo, crossfader, macro, filter, meter, and transport
controls;
- drag gestures that emit many intermediate values;
- controls expected to respond instantly while audio is playing.

For those controls, the preferred shape is:

1. mutate the live/session owner;
2. dispatch a scoped runtime update or narrow snapshot invalidation;
3. publish only the UI/runtime state that changed;
4. debounce persistence back to the document.

`SequencerDocumentSession.setTrackMix(...)` is the current example: it updates
`LiveSequencerStore`, calls a scoped engine mix update, publishes a narrow
snapshot change, and schedules document flush. New performance-time controls
should follow that pattern or explain why they cannot.

Architecture review should fail, or request a focused correction, when a
performance-time control requires full document export/apply per gesture.
The review should include an explicit verdict for this rule whenever a slice
touches session mutation, engine/runtime state, document persistence, playback,
or performance UI.

## Array-Style Sequencer Data

Step sequencer data should normally be represented as predictable arrays or array-like buffers indexed by step, track, lane, or pattern slot.

This keeps playback deterministic and makes boundary cases testable: empty, one step, page boundaries, wraparound, and maximum length.

Avoid introducing feature-specific storage that fights this shape unless the architecture document explains why.

## Audio Engine Hard Rules (timing, routing, realtime)

These are **invariants, not preferences.** Audio timing and realtime failures
are non-local (the right choice is not visible from inside the function you are
editing) and intermittent (they surface under load, mid-performance). A change
can be test-green and lint-clean and still violate these and be wrong.

**Process rule:** changing any of these six invariants requires a plan and
product-owner sign-off — never a per-edit local decision, and never a workaround
that guards the *symptom* (a deadlock, a glitch) while leaving the violating
*shape* in place. If you hit a wall that seems to require breaking one, stop and
escalate; do not band-aid.

The target architecture and the migration are in
[`docs/plans/2026-06-24-sample-accurate-timing.md`](/Users/maxwilliams/dev/in-sequence/docs/plans/2026-06-24-sample-accurate-timing.md)
(timing/sample) and the fixed-superset routing plan (routing).

### 1. One audio-derived master clock

- **DO** derive all musical time from the audio render position (engine
  `sampleTime`), through one converter object, using the tempo map.
- **NEVER** use `ProcessInfo.systemUptime`, `Date`, `DispatchTime`, or a
  `DispatchSourceTimer` deadline as a *sounding-time* source. A wall-clock timer
  may *pace* a lookahead pump; it must never decide when a note sounds.

### 2. Schedule ahead — never fire "now"

- **DO** stamp every event with a *future* time in the sink's native units
  (`AVAudioTime`/`sampleTime`, `AUEventSampleTime`, `MIDITimeStamp`) and hand it
  to the sink ahead of time via the lookahead scheduler (~100–200 ms horizon,
  ~10–20 ms pump).
- **NEVER** trigger an event the instant a timer fires. Pump jitter must not move
  the sounding frame.

### 3. AU notes are sample-stamped, never main-hopped

- **DO** schedule AU instrument notes via `AUAudioUnit.scheduleMIDIEventBlock`
  with an `AUEventSampleTime` (note-on and note-off both stamped).
- **NEVER** add a `DispatchQueue.main` hop or a bare `startNote`/`stopNote` on
  the note/tick path. (The current async-to-main hop in `AudioInstrumentHost` is
  documented debt being removed — do not copy it.)

### 4. Triggered playback reads resident buffers from RAM, never streams from disk

- **DO** play triggered samples (slices, one-shots, drum hits) from a fully
  resident `AVAudioPCMBuffer` via `scheduleBuffer`. Warm the buffer before the
  voice can fire. The PCM cache (`SampleAssetCache`) is the source of truth.
- **NEVER** reach a `scheduleSegment(file:)` / `AVAudioFile(forReading:)` on a
  trigger path. File streaming is allowed *only* for large/long audio (e.g.
  recorded input loops) as an explicitly annotated, bounded exception.

### 5. Routing is gain + bypass on a fixed graph

- **DO** pre-provision the graph (the A/B scene buses, sends, insert slots are
  always connected). Express routing changes — scene crossfade, send levels,
  per-track bus selection, mute/fill, insert enable — as **gain ramps**
  (equal-power for crossfades) and **`bypass` toggles**. Structural add/remove
  (e.g. a drum part) uses a **pre-attached node pool**, ramped to silence before
  any disconnect.
- **NEVER** `engine.stop()`/`start()` to change topology during playback, and
  **NEVER** `disconnect`/`detach` a node that is currently producing audio
  (ramp it to silence first, cut on silence).

### 6. The render thread is sacred

- no allocation, no locks, no file I/O, no ARC churn on render-thread code;
- UI→render communication via lock-free command/ring buffers; render→UI via
  buffers read from the display side;
- capture is RT-safe: sink tap → lock-free ring → dedicated disk-writer thread,
  never a disk write on the render thread;
- explicit threading contract for every runtime object.

### How these are enforced

| Layer | Mechanism |
|---|---|
| Deterministic | `scripts/diagnostics/realtime-path-lint.sh` (banned APIs on the realtime path; extended to cover wall-clock musical timing, note-path main hops, and `scheduleSegment(file:)`/`AVAudioFile` on trigger paths) |
| Deterministic | `scripts/diagnostics/runtime-ownership-lint.sh` (owner drift: UI imports in engine files, document/session reads from tick files, unannotated file IO, malformed `realtime-allow` comments) |
| Behavioural | **Offline frame-accuracy test** — render in `enableManualRenderingMode(.offline)` and assert events land within **0 frames** of target, including a zero-flam (AU note vs slice on the same step) assertion and stability across tempo change |
| Semantic | **Adherence observers** (`audio-clock-conformity`, `au-note-path-conformity`, `sample-memory-conformity`, `graph-mutation-conformity`) — read the diff/codebase and judge intent against rules 1–5; emit file:line evidence for the loop to act on. See [[observer-sweep]] |

Run the two lints whenever a change touches tick, dispatch, sample, slicer, or
audio graph code; the offline test gates every timing change; the observers run
on audio-touching diffs and on a periodic sweep. These rules are also in
[[code-review-checklist]] and must inform any audio architecture pass before
implementation begins.

## Small Boundaries Over Broad Rewrites

Prefer small focused document deltas, snapshot invalidations, and runtime adapters over broad document rewrites.

Red flags for architecture review:

- a UI concept becoming document truth because it was convenient;
- a new feature requiring wholesale project export/import on every gesture;
- duplicated playback paths for "almost the same" behavior;
- view-local state becoming the source of playback truth;
- new global mutable state without an explicit owner.

## PM Architecture Pass

Every roadmap `architecture.md` should cite the relevant code and wiki sources it used. It should make the proposed course of action reviewable before spec:

- what state is persisted;
- what state is transient;
- what runtime buffers or snapshots are involved;
- what existing patterns are being followed;
- what architecture questions remain open.
