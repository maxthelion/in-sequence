# Plan: Engine Timing Recovery Implementation

Status: Active plan — 2026-07-01  
Branch/worktree: `engine/precompute-lookahead` in `/Users/maxwilliams/dev/in-sequence/.worktrees/drum-timing`

## References Kept In Place

This plan supersedes the implementation direction of the overnight branch, but
keeps these files as evidence/reference:

- `docs/plans/2026-06-30-precompute-lookahead-recording.md` — original spec,
  acceptance criteria, gate thresholds.
- `docs/plans/2026-06-30-FLEET-BRIEF.md` — fleet operating contract.
- `docs/plans/2026-07-01-round2-integration-spec.md` — prosecution-informed
  correction after round 1 shipped hollow P2/P3 work.

The useful lesson from those runs is not "merge the branch"; it is:

- P0/P1 scaffolding is valuable.
- P2 has useful pieces but still needs simplification before trust.
- P3 was not implemented: current `leadStampedAudioTime` is a no-op wrapper unless
  the pump actually dispatches ahead of the musical due time.
- Offline rails alone are insufficient for the realtime flam; they must be paired
  with a human/real-acoustic check.

## Problem To Solve

The engine currently has intermittent first-play silence/flam behavior around AU,
sample/drum, MIDI, and Stop/Start boundaries. The recent branch also revealed
that a nominal "look-ahead" API can pass narrow rails without actually changing
the pump: events are still dispatched at their musical due time, so sinks can
still see stale/past-due `when` values and clamp to immediate.

The fix must make the lifecycle and scheduler model explicit:

- The audio graph can remain warm and silent while the app/session is active.
- Transport Start establishes a render-derived clock origin when possible.
- Transport Stop immediately prevents any further musical event scheduling.
- Event recording captures the realized stream, including note-repeat-derived
  events, not only the generator stream.
- Precompute is a helper for the next bar, not an excuse to block the tick path.
- Look-ahead means the pump hands events to sample/AU/MIDI sinks before their
  musical due time while stamping them for the true due time.

## Non-Goals

- Do not merge all overnight commits blindly.
- Do not treat probe-only calls as implementation.
- Do not move the master-clock origin forward to simulate look-ahead.
- Do not rely on unattended Peekaboo/acoustic capture as a required gate.
- Do not redesign voice allocation or plugin delay compensation in this pass.

## Current Branch State To Stabilize First

Before implementation commits, make the worktree reviewable:

- Decide whether the currently untracked verifier tests should become committed
  prosecution evidence or be moved under a non-gating evidence folder.
- Commit or discard the `project.pbxproj` membership changes so the branch is
  not dependent on local dirt.
- Keep routing-stress run files out of implementation commits unless a specific
  run is cited as evidence.

Acceptance for this step:

- `git status --short` has no ambiguous implementation dirt.
- The branch builds from committed files only.
- The plan/reference/prosecution artifacts are clearly separated from product code.

## Phase A — Transport And Graph Lifecycle

### Intent

Separate transport lifecycle from audio graph lifecycle.

Transport Stop means "stop musical scheduling and release/stop voices." It should
not normally mean tearing down the shared graph. Graph teardown belongs to
shutdown, device changes, explicit rebuilds, or unrecoverable graph errors.

### Implementation Direction

- Keep `SamplePlaybackEngine.stopVoicesKeepingEngineWarm()` or an equivalent
  explicit transport-stop method.
- Ensure `EngineController.stop()`:
  - flips the logical transport state before joining the clock queue,
  - clears pending events or invalidates the current transport generation,
  - prevents an in-flight tick from scheduling more AU/sample/MIDI output,
  - stops voices and note-repeat state,
  - leaves the audio graph warm.
- Ensure `EngineController.shutdown()` still performs full graph teardown.
- Prefer a transport generation/token over ad hoc booleans:
  - every prepared event carries the generation it was prepared for,
  - `dispatchTick` drops events whose generation does not match the current
    running transport generation,
  - Stop increments/invalidates the generation and clears queues.

### Criteria

- A tick already in flight after Stop schedules zero new audible events.
- Pending events from the old generation cannot leak into the next Start.
- Stop does not call `engine.stop()` through sample playback.
- Shutdown still tears down.
- Existing shutdown and routing tests continue to pass.

### Gates

- `EngineControllerShutdownTests`
- a focused stop-in-flight test that pumps/queues events, calls Stop, then proves
  no AU/sample/MIDI sink receives new events
- `runtime-ownership-lint`
- `realtime-path-lint`

## Phase B — Clock Origin And First-Play Readiness

### Intent

Fix first-play silence without lying to the clock. A render-derived origin is the
authoritative origin. A fallback may be used only as an explicitly aligned
immediate/cold-start path, not as a fake AU frame base.

### Implementation Direction

- Remove/comment-correct any remaining origin-shift language.
- `AudioMasterClock.captureOrigin` should not bake the look-ahead lead into the
  origin.
- Keep render-derived origin detection explicit:
  - sample/AU/MIDI should make the same cold-start decision for a given tick,
  - no one path should receive +100 ms while another path goes immediate.
- If no render origin exists at first dispatch:
  - either defer transport start briefly until one exists, or
  - intentionally schedule all relevant first-tick outputs through the same
    immediate/cold path.
- Prefer graph warmup before first transport start so the fallback is rare.

### Criteria

- First transport run after selecting an AU does not silently drop AU notes.
- AU/sample/MIDI do not split by ~100 ms in cold fallback.
- The first event origin diagnostic records whether the origin was render-derived.
- No path treats nil AU `lastRenderTime` as a valid sample-frame base.

### Gates

- existing AU note trace log path from `AGENTS.md`
- `ColdStartFallbackMIDIFlamVerifierTests` should be converted from failing
  evidence into a green gate or equivalent fixed test
- first-play manual check with AU + 808 kit
- `OfflineFrameAccuracyTests`

## Phase C — Event Recording Completeness

### Intent

Phase 0 recording must mean "record the realized stream that sounded," not just
"record generator output before later performance transforms."

### Implementation Direction

- Keep `EventRecorder` / `EventReplaySource` if they remain small and useful.
- Add a single recording seam after all runtime transforms that create audible
  notes:
  - generator/clip output,
  - note-repeat scheduled events,
  - routed AU/sample events if they are materially distinct.
- Do not record masked pre-note-repeat maps as the final realized stream.
- Replay should feed the same dispatch path and not require re-engaging note
  repeat to reproduce recorded output.

### Criteria

- A live run with note repeat records every note that sounded.
- Replaying that recording through a fresh engine produces byte-identical note
  output for the recorded tracks.
- Existing clip-history/capture assumptions still hold.

### Gates

- Convert `EventRecordingNoteRepeatReproductionTests` into green tests.
- Existing `EventRecordingRoundTripTests`
- Existing note-repeat tests

## Phase D — Precompute Simplification

### Intent

Keep precompute only if it actually removes generation from the steady tick path
without making Start/Stop fragile.

### Implementation Direction

- Keep `BarPrecomputeEvaluator.precompute` as the off-thread generator.
- Avoid blocking the main thread or transport start on precompute.
- Avoid long bounded waits on the tick path. If a precomputed bar is unavailable,
  use a clearly logged fallback for that boundary and immediately request the next
  bar.
- Keep live/performance controls at dispatch, not baked into long-lived
  precomputed bars.
- Fix generator-state continuity across bars. The current risk is per-bar reset
  changing Markov/last-note behavior.

### Criteria

- Steady-state ticks consume a published precomputed bar without calling the live
  generator seam.
- Boundary fallback is observable and rare, not the normal path.
- Precomputed and live reference streams match for deterministic fixtures.
- Markov/stateful generators keep continuity across bar boundaries.

### Gates

- `TickConsumesPrecomputeRailTests`
- `PrecomputeBarEquivalenceTests`
- `realtime-rng-lint`
- targeted stateful-generator continuity test

## Phase E — Real Look-Ahead Pump

### Intent

Implement actual early dispatch. The pump must wake before due events and hand
them to sinks early, while the event's audio/MIDI stamp remains its true musical
due time.

### Required Model

Separate these concepts:

- `dueMusicalSeconds`: when the event should sound in musical time.
- `dueAudioTime` / `dueSampleTime` / MIDI timestamp: the clock-derived stamp for
  that due time.
- `pumpNow`: when the pump woke.
- `lookAheadLeadSeconds`: how far ahead of due time the pump is allowed to hand
  events to sinks.
- `transportGeneration`: whether the event still belongs to the live transport.

The pump should dispatch events whose due time falls inside:

```text
pumpCursor ... pumpCursor + lookAheadLeadSeconds
```

It must not dispatch the same event twice. It must not dispatch old-generation
events after Stop. It must still allow immediate live controls to apply at the
time of dispatch.

### Implementation Direction

- Replace "dispatch current step at current tick" with a horizon-based dispatch:
  - maintain the highest prepared/dispatched step for the active generation,
  - on each pump wake, prepare/dispatch all steps due within the lead window,
  - stamp each event for its due musical position, not for pump time.
- `leadStampedAudioTime` should become either:
  - a real helper that accepts `dueMusicalSeconds` and `pumpNow` and validates
    due is in the lead window, or
  - be removed in favor of clearer `audioTime(atDueMusicalSeconds:)` plus pump
    horizon logic.
- `TickClock` may remain the wake source, but its wake interval should be pump
  pacing, not step identity. A shorter wake interval than the step grid may be
  needed.
- Do not shift `AudioMasterClock` origin.

### Criteria

- For normal playback, `SamplePlaybackEngine.effectivePlaybackTime` sees future
  `when` values, not nil/immediate, for sample/slice events.
- AU note stamps are future sample frames when a render origin exists.
- MIDI timestamps use the same due-time model and do not get a different cold
  fallback than audio.
- The 808 flam under UI/nav load is below the agreed threshold.

### Gates

- A deterministic pump-horizon unit test:
  - simulate pump waking before a due step,
  - assert sink receives the event before due,
  - assert event stamp equals due, not pump time,
  - assert no duplicate dispatch on later pump wakes.
- A negative test where `leadStampedAudioTime` / equivalent no-op wrapper fails.
- `LookAheadSchedulingTests`, repaired to assert the real pump behavior.
- Human acoustic check with real app and 808 kit.

## Phase F — Integration And Cleanup

### Intent

Leave one coherent implementation, not a pile of rails and contradictory
comments.

### Implementation Direction

- Delete or quarantine stale rail stubs once they have served their purpose.
- Remove comments that describe origin shift as the Phase 3 solution.
- Keep only tests that are green and encode ongoing invariants.
- Move failing prosecution reproductions to an evidence doc or convert them into
  green regression tests.
- Ensure `project.pbxproj` contains every committed Swift source/test file.

### Final Acceptance Checklist

- [x] Worktree clean except deliberate generated evidence ignored by git.
- [x] App target builds from committed files only.
- [x] `realtime-path-lint.sh` green.
- [x] `runtime-ownership-lint.sh` green.
- [x] `realtime-rng-lint.sh` green.
- [x] Focused tests green:
  - transport stop/in-flight scheduling
  - first-play cold fallback alignment
  - event recording + note repeat
  - precompute steady-state consumption
  - real look-ahead pump horizon
- [x] `OfflineFrameAccuracyTests` green.
- [ ] Human/manual acoustic pass:
  - AU first play sounds on first transport run,
  - 808 kit sounds immediately,
  - Stop does not release a delayed bar of audio,
  - flam is not perceptible and/or measured below threshold.
- [x] Final implementation comments describe one model:
  warm graph, render-derived origin, transport generation, realized-event
  recording, precomputed bar consumption, horizon-based look-ahead dispatch.

## Merge Policy

Do not merge the current branch wholesale. Merge only after this recovery plan's
acceptance checklist is satisfied and the branch has been distilled into coherent
commits. If the work remains tangled, extract phases onto a fresh branch in this
order:

1. graph/transport lifecycle,
2. event recording completeness,
3. precompute,
4. look-ahead pump.

P3 should not ride along with P0/P1 unless it has the real acoustic check.

## Implementation Status — 2026-07-01

Committed recovery work on `engine/precompute-lookahead`:

- `0d92168d` — stabilized the branch evidence: prosecution repros are preserved
  under `docs/plans/engine-timing-recovery-evidence/`, while active Xcode
  membership keeps only product code needed by the build.
- `1d9c410c` — Phase A transport generation: queued audible events carry a
  transport generation; dispatch drains only the current generation so old
  prepared events cannot leak across Stop/Start.
- `23092b34` — Phase B guardrail cleanup: the active start-call test now asserts
  the unshifted-origin model; comments no longer describe origin shift as the
  production fix.
- `080f0a5d` — Phase C event recording: note-repeat realized output is recorded
  through the same recorder contract, with a focused engine-wiring regression.
- Phase D precompute rails were already functional in this branch after
  stabilization; `TickConsumesPrecomputeRailTests` and
  `PrecomputeBarEquivalenceTests` now pass without further product-code changes.
- `1d81cd6d` — Phase E first pump slice: `TickClock` keeps tick 0 immediate, then
  wakes tick 1 at `stepInterval - lookAheadLeadSeconds` and continues at the
  normal step interval.

Deterministic verification run after implementation:

- `xcodebuild test ... -only-testing:SequencerAITests/EventQueueTests`
- `xcodebuild test ... -only-testing:SequencerAITests/TickClockTests`
- `xcodebuild test ... -only-testing:SequencerAITests/LookAheadStartCallSiteGuardTests`
- `xcodebuild test ... -only-testing:SequencerAITests/LookAheadEarlyDispatchTests`
- `xcodebuild test ... -only-testing:SequencerAITests/EventRecordingEngineWiringTests`
- `xcodebuild test ... -only-testing:SequencerAITests/PrecomputeBarEquivalenceTests`
- `xcodebuild test ... -only-testing:SequencerAITests/TickConsumesPrecomputeRailTests`
- `xcodebuild test ... -only-testing:SequencerAITests/OfflineFrameAccuracyTests`
- `xcodebuild build -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS'`
- `scripts/diagnostics/realtime-path-lint.sh`
- `scripts/diagnostics/runtime-ownership-lint.sh`
- `scripts/diagnostics/realtime-rng-lint.sh`

Known remaining gates before merge to main:

- Run a real app/audio manual pass with AU + 808 kit:
  - AU first play sounds on the first transport run,
  - drums do not wait until Stop,
  - no obvious flam under UI/nav load,
  - mixer levels still reflect active tracks.
- If the manual pass still exposes flam, add a sink-level deterministic rail that
  observes `effectivePlaybackTime` receiving non-nil future `AVAudioTime` for
  post-tick-0 sample/slice events.
