# Plan: Sample-Accurate Event Timing

**Status:** Proposed — 2026-06-24
**Goal:** Make musical event triggering sample-accurate across all three sinks
(sample/slice playback, AU instruments, MIDI out) by deriving all timing from
the audio render clock and scheduling ahead. Removes the AU-vs-slice "flam".
**Guardrail:** This plan establishes the invariants recorded in
[architecture-guardrails.md → Audio Timing & Graph Mutation](/Users/maxwilliams/dev/in-sequence/wiki/pages/architecture-guardrails.md).
Read those first; this plan is how we get there, the guardrails are what we keep.

## Non-goals (explicit scope boundary)

Sample-accurate **triggering** is the goal. The following are **NOT** in this
plan and must not be started under its banner:

- A custom `AVAudioSourceNode` + C/C++ mix/crossfade core. (Later, only if a
  sample-accurate crossfade or custom DSP is actually required. A click-free
  crossfade needs *smoothness* — an equal-power gain ramp — not sample accuracy.)
- The fixed-superset routing refactor (separate plan; stop/start-on-topology is
  a different problem from event timing).
- Plugin delay compensation (PDC) for AU internal latency. A later refinement.

If a change requires any of the above to land Phase 0/1, stop and re-scope.

## Background: where timing comes from today

| Sink | Sample-accurate now? | Evidence |
|---|---|---|
| Samples / slices | **Yes** | `SamplePlaybackEngine.scheduleSegment(_:at:)` / `play(at:)` take a future `AVAudioTime` |
| AU instruments | **No** | `AudioInstrumentHost.play(...)` hops `instrument.startNote` to main async (`AudioInstrumentHost.swift:431`), note-off via wall-clock `queue.asyncAfter` (`:435`) |
| MIDI out | Host-time stamped | `MidiOut` packets carry `MIDITimeStamp`; close, hardware sets the floor |

The master clock is **wall-clock**, not audio-derived:
- `TickClock` is a `DispatchSourceTimer` firing at step rate; its tick carries
  `ProcessInfo.processInfo.systemUptime` (`TickClock.swift:48,61,74`).
- `EngineController.scheduledAudioTime(for:)` converts that wall-clock seconds
  value to a host time (`EngineController.swift:413-418`).

So even though slices accept a precise `AVAudioTime`, the *time value* they get
originates from a jittery wall clock that can drift against the audio device.
The two foundational problems, in order:

1. **No single audio-derived clock** → all stamping is against a drifting base.
2. **AU note path is async-to-main** → AU notes land on a main-queue hop, not a
   stamped frame, so they flam against sample-accurate slices.

## The fix, in two load-bearing phases

### Phase 0 — One audio-derived master clock + lookahead scheduler

This is the foundation; Phases 1–3 depend on it. Pure Swift, stays inside
AVAudioEngine. No C++.

**Current shape:** `TickClock.start { tickIndex, now in processTick(...) }` fires
at musical step rate; `processTick` prepares the next step one tick ahead
(`EngineController` `prepareTick`/`dispatchTick`).

**Target shape:**
1. Expose the engine's render position as the clock origin. Read it from the
   output/mixer node (`AVAudioNode.lastRenderTime` →
   `playerTime(forNodeTime:)`), giving a monotonic `sampleTime` + matching
   `hostTime`. Wrap it in one converter object that answers:
   - `sampleTime(at musicalPosition:) -> AVAudioFramePosition`
   - `now() -> (sampleTime, hostTime)` from the live render position.
   All conversions go through this one object and the tempo map. Nothing else
   reads `systemUptime`/`Date`/`DispatchTime` for musical timing.
2. Convert the tick loop into a **lookahead pump**: a timer wakes every
   **~10–20 ms** and dispatches every event whose musical position falls inside
   the next **~100–200 ms** window, each stamped in `sampleTime`. The pump's own
   jitter no longer affects sounding time — it only affects how far ahead we
   commit. (Today's 1-step horizon at `prepareTick(tickIndex &+ 1)` becomes this
   wider, finer window.)
3. `scheduledAudioTime(for:)` stops converting a wall-clock value and instead
   builds `AVAudioTime` from the unified clock's `sampleTime`
   (`AVAudioTime(sampleTime:atRate:)`), keeping the existing
   `scheduledAudioTimeOverrideForTesting` seam (`EngineController.swift:410`) for
   the offline harness.

**Keep:** `TickPathMainSyncGuard`, the `EventQueue` prepare/dispatch split, the
`scheduledAudioTimeOverrideForTesting` hook, manual-rendering mode.

**Host-time anchoring decision (Phase 0 as built).** The live AUDIO stamp is a
*host time* (`AVAudioTime(hostTime:)`) computed as `originHostSeconds +
musicalSeconds`, NOT a raw device `sampleTime`. This is deliberate and stays:
an `AVAudioPlayerNode`'s `sampleTime` reference is its OWN player timeline, not
the output node's, so a frame read from the output render position cannot be
handed to `scheduleSegment/Buffer(at:)`; a host time can, and AVFoundation
correlates it to the render clock live, jitter-free. Rule 1 is still honoured:
the host-time ORIGIN is captured from the render position's `hostTime` (the
render clock), and the musical OFFSET comes from the tempo map — neither is a
free-running wall clock. `AudioMasterClock` is THE one sanctioned site that may
touch `systemUptime`/host time for musical timing: the provisional pre-render
origin fallback, the render-origin capture/upgrade, and the final
`AVAudioTime(hostTime:)` stamp. Everything else derives its sounding time from
this object. The render-derived `sampleTime(atMusicalSeconds:)` API is retained
for the offline/deterministic gate and diagnostics (it IS the conversion the
offline frame-accuracy gate exercises), not the live path. The wider
~100–200 ms lookahead pump is NOT built in Phase 0 — the retained 1-tick prepare
horizon already stamps each step from the tempo map (pump-jitter-independent),
which meets the stamping goal; the dead `now()` pump-read API was removed rather
than left claiming a window that does not exist.

**Routed-audio vs MIDI unit separation (Phase 0 as built).** Routed AUDIO
events (routed slicer / routed AU / routed note-repeat audio) stamp the unified
clock's MUSICAL seconds — the SAME unit own-pattern audio uses — so an
own-pattern and a routed trigger on the same step land on the same frame (zero
flam, regression-gated by
`EngineControllerSampleTriggerTests.test_ownPatternAndRoutedSlice_onSameStep_landOnSameFrame_zeroFlam`).
MIDI-out is NOT on the unified clock yet (Phase 3): it keeps its own wall-clock
host-time path (`RouterDispatchState.dispatchNow`) for its `MIDITimeStamp`. The
two units are threaded separately through `RouterDispatchState`
(`dispatchMusicalSeconds` for audio, `dispatchNow` for MIDI) — the musical value
must never reach a `MIDITimeStamp`, and the host-time value must never reach the
`scheduledAudioTime(for:)` audio seam.

**Acceptance gate (must pass before Phase 1):**
- New offline-render test: drive the engine in `enableManualRenderingMode(.offline)`,
  schedule events at known musical positions, assert each lands within **0
  frames** of its target sample, and that the mapping stays exact across a
  mid-stream tempo change.
- The tick-clock jitter probe shows scheduling decisions decoupled from pump
  wake jitter (pump can be late without moving the sounding frame).

### Phase 1 — AU notes sample-stamped (the flam fix)

**Change `AudioInstrumentHost.play(noteEvents:bpm:stepsPerBar:)`
(`AudioInstrumentHost.swift:406`):**
- Replace `performOnMainAsync { instrument.startNote(...) }` (`:431`) with the
  AU's **`scheduleMIDIEventBlock`** (`AVAudioUnit.auAudioUnit.scheduleMIDIEventBlock`),
  passing an `AUEventSampleTime` derived from the event's unified-clock
  `sampleTime`. This schedules the note-on at an exact frame inside the AU's
  render — no main hop.
- Replace the wall-clock note-off (`queue.asyncAfter`, `:435`) with a second
  `scheduleMIDIEventBlock` note-off stamped at `sampleTime + length` (frames),
  so gate length is sample-accurate too.
- **Delete the main-thread hop on the note path.** It exists only as the "D3"
  deadlock workaround (`:428-433`); sample-stamped scheduling removes the reason
  for it. The host-queue / main hops for *graph setup and preset* work stay.

**Acceptance gate:**
- Offline-render test: an AU note-on and a slice trigger placed on the same step
  land on the **same frame** (zero-flam assertion).
- `realtime-path-lint` confirms no `DispatchQueue.main`/`startNote`-on-main on the
  note/tick path (see lint extension below).

### Phase 2 — Sample/slice path: feed from the unified clock AND play resident buffers, not disk streams

Two parts:

**2a — Unified clock.** Verify `SamplePlaybackEngine.play(...at:)` /
`scheduleSegment(at:)` receive the unified clock's `AVAudioTime` (built from
`sampleTime`), not a host time derived from wall clock. Small once Phase 0
lands. Add it to the zero-flam offline test.

**2b — Read from memory, not disk, on every trigger.** The mechanism
(`AVAudioPlayerNode`) is the correct, sample-accurate tool — but it is being
*used wrong* on the hot path. Today `startSliceVoice` only plays the resident
PCM buffer (`scheduleBuffer`, `SamplePlaybackEngine.swift:684`) when `reverse`
or an attack/release envelope is set (`:666`). The **common forward case falls
to `scheduleSegment(file:)` (`:686`), which lazily streams the `AVAudioFile`
from disk as it plays** — background disk I/O + a file handle per voice, higher
and less predictable trigger latency, and it defeats the in-memory PCM cache
that `SampleAssetCache` already builds (`loadPCMBuffer()` at warm time, LRU
budget). For a performance instrument firing slices/one-shots rapidly, that is
exactly the wrong default.

Target:
- **All *triggered* playback (slices, one-shots, drum hits) plays a fully
  resident `AVAudioPCMBuffer` via `scheduleBuffer` — always read from RAM, never
  stream from disk.** Make the resident buffer the precondition for triggering:
  a slice that isn't warmed is warmed before it can fire, not streamed.
- **`scheduleSegment(file:)` / file streaming is reserved for large/long audio**
  where resident cost is prohibitive — e.g. recorded audio-input loops — as an
  explicit, bounded, commented exception, not the fallback default.
- Remove the legacy disk-open fallback on anything reachable during playback
  (`cachedFile(url:)` / `AVAudioFile(forReading:)`, `:1038-1042`); confirm via
  the realtime lint that no trigger path opens a file.
- Keep buffer transforms (reverse, envelope) operating on the resident buffer,
  as today.

**Acceptance gate:**
- A triggered slice with default settings (forward, no envelope) schedules via
  `scheduleBuffer` (resident), asserted in test — no `scheduleSegment(file:)` on
  the trigger path.
- `realtime-path-lint` shows no `AVAudioFile(forReading:` / `scheduleSegment(`
  reachable from the slice/sample trigger path (annotate the one allowed
  large-loop streaming site with `realtime-allow-… Test:`).
- Warm-before-trigger: firing an un-warmed slice warms it first; it never
  silently streams from disk.

### Phase 3 — MIDI out stamped from the unified clock

`MidiOut` already stamps `MIDITimeStamp`; point its timestamp source at the
unified clock's `hostTime` so external gear shares the timeline. Expose a
per-port output offset for hardware calibration (out of scope to *tune*, in
scope to *plumb*).

## Enforcing mechanisms (so it can't regress)

1. **Offline frame-accuracy test** (Phase 0 + 1 gates above) — the primary
   guard. Sample accuracy is deterministic under offline render; assert exact
   frames, not tolerances.
2. **Extend `scripts/diagnostics/realtime-path-lint.sh`:**
   - forbid `ProcessInfo.processInfo.systemUptime`, `Date(`, `DispatchTime.now`
     as a *musical-timing* source on tick-path files;
   - forbid new `DispatchQueue.main.async/.sync` and `startNote(`/`stopNote(`
     calls on the AU note path in `AudioInstrumentHost.swift` (the existing ones
     get removed in Phase 1; after that, none are allowed without a
     `realtime-allow-…` annotation + test reference).
   - **Status (#39, 2026-06-26): Rule 1 (wall-clock musical-timing on the
     tick/scheduling path) and Rule 4 (`scheduleSegment(file:)` /
     `AVAudioFile(forReading:)` on the sample-trigger path) are NOW ENFORCED.**
     Every current sanctioned site is annotated (`realtime-allow-…` +
     `Test:`); a new unannotated occurrence fails the lint
     (`RealtimePathLintTests` covers both with planted-violation fixtures).
     Rule 3 (AU note-path main-hop / `startNote`/`stopNote`) is still **DEFERRED
     to Phase 1 (#36)** — the lint carries a marked `ADD IN PHASE 1` comment
     because the offending calls still exist in pre-P1 `AudioInstrumentHost`.
3. **`runtime-ownership-lint.sh`** continues to catch owner drift.

## Risks / honest caveats

- Third-party hosted AUs vary in how faithfully they honor sample-accurate MIDI;
  first-party AUs + the sample engine will be tight. Acceptable for now.
- AUs with internal latency will need PDC eventually (separate, later).
- Phase 0 is a real re-plumb of the scheduler and carries the most risk; land it
  behind the offline test before touching Phase 1.

## Adherence observers

Lints and tests catch the *literal* regressions (a banned API, a frame
mismatch). They do not catch a new code path that re-derives time from a wall
clock indirectly, or a routing edit that stops the engine through a helper, or a
new sample feature that streams from disk "just this once". For that we run
**semantic observers** that read the diff/codebase and judge intent against the
guardrails. Observers write evidence only; they do not route or fix — synthesis
and scheduling happen in the OODA loop (see [[observer-sweep]]; if the harness
is not present on the working branch, wire these as build-loop observers).

Run these whenever a change touches tick / scheduling / sample / slicer / audio
graph code (and on a periodic sweep):

1. **`audio-clock-conformity`** — flag any *musical* timing derived from
   `ProcessInfo.systemUptime`, `Date`, `DispatchTime`, or a `DispatchSourceTimer`
   deadline rather than the unified audio clock. Confirm every scheduled event
   is stamped with a *future* `sampleTime`/`AUEventSampleTime`/`MIDITimeStamp`,
   not fired "now". Evidence: file:line + which clock the value originated from.

2. **`au-note-path-conformity`** — flag any `DispatchQueue.main` hop or
   `startNote`/`stopNote` on the AU note/tick path; confirm AU notes go through
   `scheduleMIDIEventBlock` with a sample-time stamp. (Phase 1 removes the
   existing debt hop; this observer keeps it from returning.)

3. **`sample-memory-conformity`** — flag `scheduleSegment(file:)` /
   `AVAudioFile(forReading:)` reachable from a trigger path; confirm triggered
   playback uses a resident `scheduleBuffer`. Allow only the explicitly-annotated
   large-loop streaming exception.

4. **`graph-mutation-conformity`** — flag `engine.stop()`/`start()`,
   `attach`/`detach`/`connect`/`disconnect` tied to topology changes *during
   playback*, and any `disconnect` of a node not first ramped to silence.
   (Belongs to the separate fixed-superset routing plan, but the observer is
   shared — it guards the whole audio layer.)

Each observer emits a PASS/violation list with file:line and a one-line rationale
tying the finding to the specific guardrail it breaches. A violation is
evidence for the loop to schedule a correction, not an auto-fix.

## Sequencing

Phase 0 → (gate) → Phase 1 → (gate) → Phase 2 (2a then 2b) → Phase 3. Each phase
is one bounded change with its own offline-test acceptance. Do not batch them.
The four adherence observers should exist and pass before Phase 0 is considered
"locked in", and run on every subsequent audio-touching change.
