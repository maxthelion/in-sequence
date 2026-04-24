# Sub-Cell Modulation and LFOs

> **Depends on:** the live-store v2 remediation, the UI read-path cutover, and the shape of `PlaybackSnapshot`, `TrackPhrasePlaybackBuffer`, and `TrackMacroApplier` after those are landed.
>
> **Recommended predecessor:** [2026-04-24-incremental-snapshot-compilation.md](./2026-04-24-incremental-snapshot-compilation.md). Adding modulator descriptors to the compile output will make full-recompile cost worse. Incremental compile lets us add per-cell curve and LFO descriptors without regressing tap-to-invalidation latency.

## Summary

Today the phrase buffer collapses every cell expression to one scalar per step per macro binding: `macroValues: [[Double]]`. Cells like `.interpolated(from, to, curve)` get flattened — the curve is sampled once per step and the sub-step shape is lost. Track-level LFOs don't exist. Any modulation finer than the step grid is impossible.

This plan adds sub-step modulation at two layers:

1. **Sequencer-rate (tick-rate) modulation** — the snapshot holds typed modulator *descriptors* per step per binding instead of pre-evaluated scalars. The tick (which runs faster than the step, e.g. 6–96 ticks per step at 96 PPQN) samples each descriptor with the current sub-step position and emits a value. Use this for bindings upstream of the audio graph: generator parameters, chance gates, note selection, anything the sequencer itself reads.

2. **Audio-rate modulation** — a new `LFONode` in the audio graph modulates AU parameters and sampler filter settings continuously at audio buffer rate. The sequencer never ticks this LFO; it just installs and parametrises it. Use this for filter cutoff, amp, AU-automatable params — anything where 96 PPQN still sounds steppy.

Both are additive. Existing `.constant`-shaped bindings continue to work unchanged.

## Guardrails

- **No regression on constant bindings.** A binding whose authored shape is `.single`/`.bars`/`.steps` with no LFO must produce bit-identical tick output before and after this plan.
- **Snapshot stays precomputed and thread-safe.** The sub-cell work goes into modulator *descriptors* on the snapshot, not time-series values. The tick samples descriptors; the snapshot doesn't grow by a factor of ticks-per-step.
- **Tick cost stays O(tracks × bindings) per tick, not per step.** Calling `macroSamples[step][binding].sample(...)` every tick is the intended shape. For 8 tracks × 4 bindings at 96 PPQN that's a few thousand calls per second — trivial. Keep it that way.
- **Phase is computed from transport time, not baked into the snapshot.** Free-running LFOs must remain phase-stable across unrelated edits. Re-publishing a snapshot must not reset LFO phase.
- **Audio-rate LFOs live in the audio graph, not the sequencer.** The sequencer sets `rate/shape/depth/target`; the audio graph does the modulation. Sequencer edits never schedule audio-rate samples directly.
- **Incremental compilation applies.** Changing one LFO rate rebuilds exactly that binding's descriptor, not the whole snapshot. (Requires the incremental-compile plan to be in place, or this plan regresses perf.)
- **Authored vs compiled separation.** Authored: `PhraseCellValue.interpolated(...)`, `StepSequenceTrack.lfos: [LFODescriptor]`. Compiled: `MacroSample` descriptors in the snapshot, `LFONode` in the audio graph. UI reads authored, tick reads compiled.
- **No per-cell `@Observable` objects.** Track LFOs live on the `StepSequenceTrack` value; authored edits go through typed session methods.
- **1000-line file cap.**

## Architecture

```
Authored (store)
----------------
StepSequenceTrack
  lfos: [LFODescriptor]          ← new
    LFODescriptor { id, rate, shape, depth, center, targetBindingID, routingMode }

PhraseModel
  cells: [PhraseCell]            ← unchanged; .interpolated already exists

Compiled (snapshot)
-------------------
TrackPhrasePlaybackBuffer
  patternSlotIndex: [UInt8]      ← unchanged
  mute: [Bool]                   ← unchanged
  fillEnabled: [Bool]            ← unchanged
  macroSamples: [[MacroSample]]  ← replaces macroValues: [[Double]]

MacroSample
  .constant(Double)
  .ramp(from: Double, to: Double, curve: Curve, stepStartPhase: Double, stepEndPhase: Double)
  .lfo(rate: Double, shape: LFOShape, depth: Double, center: Double, targetAtStep: Double)
  .combined(base: MacroSample, overlay: MacroSample, combine: CombineMode)
  sample(stepFraction: Double, transportTime: Double) -> Double

Tick layer
----------
EngineController.prepareTick
  for each binding per track:
    value = macroSamples[step][binding].sample(stepFraction: subStepPos, transportTime: now)
    macroApplier.apply(bindingID, trackID, value)

Audio graph layer
-----------------
SamplePlaybackEngine
  LFONode per routed LFO:
    runs at audio buffer rate
    modulates an AUParameter or SamplerFilterControlling target
    parameters updated from the snapshot's LFODescriptor on each publish
```

## Early Guardrail Tests

Per phase, failing tests first.

### Phase 1 — `MacroSample` type + compile rules

- `MacroSampleSemanticsTests`
  - `.constant(x).sample(...)` returns `x` regardless of stepFraction/transportTime.
  - `.ramp(from: 0, to: 1, curve: .linear).sample(stepFraction: 0, ...)` returns 0; at 0.5 returns 0.5; at 1 returns 1. Non-linear curves tested similarly.
  - `.lfo(rate: 1 Hz, shape: .sine, depth: 1, center: 0, targetAtStep: 0).sample(transportTime: 0.25)` returns sin(π/2) ≈ 1; at transportTime: 0 returns 0; at 0.5 returns 0.
  - `.combined(base: constant(0.5), overlay: lfo(depth 0.5), .add).sample(...)` sums base + overlay.
- `PhraseBufferCompileTests`
  - `.single(x)` cell compiles to `[.constant(x), .constant(x), ...]` for all affected steps.
  - `.bars([a, b])` compiles to `.constant(a)` for bar 0 steps, `.constant(b)` for bar 1 steps.
  - `.interpolated(from: 0, to: 1, curve: .linear)` compiles to per-step `.ramp(...)` entries whose stepStartPhase/stepEndPhase cover 0→1 across the cell's range. Each step's `.ramp` contributes 1/stepCount of the total.
  - A track with one LFO targeting binding B: on every step, `macroSamples[step][B]` becomes `.combined(base, .lfo(...))` or `.lfo(...)` depending on whether an authored cell exists.
  - Bit-identity regression: a project with only `.single` cells and no LFOs produces a snapshot whose `macroSamples` equal `.constant(x)` everywhere, and `TrackMacroApplier` output at each tick matches the pre-plan output exactly.

### Phase 2 — tick samples per-tick

- `TickRateMacroApplicationTests`
  - Given a snapshot with `.ramp(from: 0, to: 1)` on a binding, 6 ticks per step: the 6 tick-time apply calls produce values `[0, 1/6, 2/6, 3/6, 4/6, 5/6]` (not `[0, 0, 0, 0, 0, 0]` as today).
  - Given `.lfo(rate: 1, shape: sine)`: tick values trace a sine over transportTime as expected.
  - Given `.constant(x)`: all 6 tick values equal `x` (no behaviour change from current code).
  - Over a whole phrase run at 96 PPQN, the total number of `TrackMacroApplier.apply` calls is `ticksPerStep * stepCount * bindings * tracks`. Assert the count matches the expected tick-rate (today it's `stepCount * bindings * tracks` — step-rate).

### Phase 3 — cell curves no longer collapsed

- `CellCurveInterpolationTests`
  - Authored `.interpolated(from: 0, to: 1, curve: .linear)` over a 4-step cell produces sub-step values that actually interpolate within each step, not just between steps. Concretely: tick 3 of step 0 (50% into step 0, 12.5% into the 4-step cell) samples to ~0.125, not 0.
  - Non-linear curves (exponential, ease-in-out) tested similarly.
  - Backwards compatibility: existing phrase fixtures continue to produce expected final-step values. The interpolation gives smoother intermediate values, but endpoints are unchanged.

### Phase 4 — track-level LFOs (sequencer-rate)

- `TrackLFOSequencerRateTests`
  - Adding an LFO descriptor to a track that targets binding B: snapshot's `macroSamples[step][B]` becomes `.lfo(...)` (or `.combined(base, lfo)`). Tick output traces the LFO shape over transportTime.
  - Removing the descriptor: snapshot's `macroSamples[step][B]` reverts to the pre-LFO shape (constant or ramp).
  - Phase stability: start transport, edit an unrelated clip, observe that the LFO's tick output at time T is the same before and after the edit. Phase is time-based, not snapshot-generation-based.
  - Depth/rate changes update the descriptor without resetting phase.

### Phase 5 — audio-rate LFOs

- `AudioRateLFOTests`
  - Install an LFO descriptor with `routingMode: .audioRate` targeting a filter cutoff binding: the sampler filter's AUParameter receives continuous modulation (verify by sampling the parameter at multiple audio buffer timestamps or by instrumenting the AU).
  - Sequencer tick path does NOT write to this binding per tick (it's bypassed — the audio graph owns modulation).
  - Removing the descriptor: audio-rate modulation stops.
  - Rate/depth changes: audio-graph LFO node reconfigured in place without glitches (AU parameter ramp, not instantaneous step).

### Phase 6 — UI

- `ModulationAuthoringUITests`
  - User adds an LFO to a track, assigns target binding, sets rate/shape/depth. Session typed method `addTrackLFO` publishes the snapshot; tick observes the modulation. UI reflects the LFO in the track inspector.
  - User authors `.interpolated(from, to, curve)` via cell editor. The curve is preserved through compile (tested in Phase 3); UI shows the curve preview.

## Implementation Phases

### Phase 1 — `MacroSample` type and compile rules

- Define `MacroSample`, `LFOShape`, `Curve`, `CombineMode` types in `Sources/Engine/MacroSample.swift`.
- Replace `TrackPhrasePlaybackBuffer.macroValues: [[Double]]` with `macroSamples: [[MacroSample]]`.
- Update `SequencerSnapshotCompiler.compilePhraseBuffer` to emit `.constant` for all current cells. No behaviour change yet.
- Add `MacroSample.sample(stepFraction:transportTime:) -> Double`.
- Update `TrackMacroApplier.apply` signature if needed (it already takes a dict; unchanged most likely).
- Update `resolvedStep` / `layerSnapshot` in `PlaybackSnapshot.swift` to read from the new field and call `.sample(...)` with zero-fraction / zero-time (preserves current scalar output shape).

This phase ships **as a refactor with no observable behaviour change.** All tick outputs are bit-identical to pre-plan.

### Phase 2 — tick samples at tick rate

- In `EngineController.prepareTick`, compute `subStepPos: Double` from the current tick's position within the step. (Transport already tracks tick index; `subStepPos = (tickIndex % ticksPerStep) / ticksPerStep`.)
- Call `macroSamples[step][binding].sample(stepFraction: subStepPos, transportTime: now)` per binding per tick.
- `TrackMacroApplier.apply` is called at tick rate instead of step rate. For bindings bound to AU parameters, the per-tick writes use timestamped ramps so audio-rate smoothness emerges downstream.

Existing behaviour: all samples are `.constant`, so per-tick values match the previous step-rate values. No audible change, just higher-frequency writes of the same values.

### Phase 3 — preserve cell curves

- Change `compilePhraseBuffer` to emit `.ramp(from, to, curve, stepStartPhase, stepEndPhase)` for `.interpolated` cells, where stepStartPhase/stepEndPhase encode the step's position within the cell's range.
- `MacroSample.ramp.sample(stepFraction:transportTime:)` returns `from + curve.evaluate(stepStartPhase + stepFraction * (stepEndPhase - stepStartPhase)) * (to - from)`.
- Sub-step resolution of authored interpolation now actually works.

### Phase 4 — track LFOs, sequencer-rate

- Add `StepSequenceTrack.lfos: [LFODescriptor]` field.
- Add `LFODescriptor { id: UUID, rate: Double, shape: LFOShape, depth: Double, center: Double, targetBindingID: UUID, routingMode: LFORoutingMode }` with `LFORoutingMode { case sequencerRate, audioRate }`.
- In `compilePhraseBuffer`, for each sequencer-rate LFO, overlay `.lfo(...)` or `.combined(baseCell, lfo)` onto the affected binding's macroSamples. Phase is computed at tick time from `transportTime * rate`, not baked.
- Session typed methods:
  - `addTrackLFO(trackID:descriptor:)`
  - `updateTrackLFO(trackID:id:mutate:)`
  - `removeTrackLFO(trackID:id:)`
  Each uses `mutateTrack` internally and publishes a snapshot.
- Incremental compile: changing one LFO rate rebuilds only that track's phrase-buffer samples for the affected binding. (Depends on the incremental plan.)

### Phase 5 — audio-rate LFOs

- Add `LFONode` to `SamplePlaybackEngine` — a small class that wraps an `AVAudioUnit`-style node or an `AUParameter.setValue(atHostTime:)` scheduling helper. Runs at audio buffer rate.
- For each `LFODescriptor` with `routingMode: .audioRate`, the snapshot carries the descriptor and `TrackMacroApplier` installs the corresponding `LFONode` into the audio graph on publish. Updates reconfigure rate/depth in place.
- The sequencer tick path **skips** audio-rate LFOs — `MacroSample` for audio-rate bindings is `.audioRateDelegated(lfoID)`, and the tick doesn't write them. The audio graph owns the target parameter's modulation.
- Removing or switching an LFO from audio-rate cleanly removes the node from the graph.

This phase has a non-trivial audio-engine surface. If it proves too large, split into its own plan and ship Phase 4 first — sequencer-rate modulation is already a real capability win.

### Phase 6 — UI

- Track inspector gains an LFO section: list, add, remove, per-LFO rate/shape/depth/target/routing controls.
- Phrase cell editor gains a curve control for `.interpolated` cells.
- Preview: the modulation value can be overlaid on the phrase grid so the user sees the curve over time.

UI work depends on the data model from phases 1–5. Ships last.

## Test Plan

Phase gates:

- Phase 1: `MacroSampleSemanticsTests` and `PhraseBufferCompileTests` green. Full-suite tick outputs bit-identical to pre-plan (assert on a recorded macro-dispatch sequence for a reference project).
- Phase 2: `TickRateMacroApplicationTests` green. Full-suite output still identical on constant bindings.
- Phase 3: `CellCurveInterpolationTests` green. Regression fixtures (pre-plan projects with only `.single` cells) still match exactly.
- Phase 4: `TrackLFOSequencerRateTests` green. Reference project with one authored LFO produces expected tick output across a full phrase run.
- Phase 5: `AudioRateLFOTests` green. Manual listening test: LFO modulating filter cutoff sounds continuous, no steppy artifacts.
- Phase 6: UI smoke tests + one end-to-end: author an LFO in the inspector, run transport, observe the modulation via the live view.

Manual signals:

- After Phase 3: authored `.interpolated` cells sound smoother through a full phrase — no stepping on parameter changes.
- After Phase 4: a macro-bound knob on a generator can be modulated by an LFO at arbitrary rates relative to the bar.
- After Phase 5: filter sweeps sound like filter sweeps, not step-quantised staircases.

## Assumptions

- The clock thread runs at a higher rate than the step rate. Current TickClock is configured per-project; 96 PPQN (6 ticks per 16th-note step) is typical. If PPQN is currently 1 tick per step, Phase 2 needs to raise it — add to Phase 2's scope.
- `TrackMacroApplier` dispatching at tick rate is performant. If it becomes a bottleneck (unlikely at thousands of calls per second), move audio-rate routing to audio-graph LFOs (Phase 5) for the expensive destinations.
- Free-running phase across edits is acceptable. Users expect LFOs not to jump when they edit unrelated parameters. Tempo-synced LFOs (phase locked to bar position) derive their phase from transport beat position, not wall time — same mechanism, different input.
- Authored LFOs are track-level, not phrase-cell-level. A future extension could allow phrase cells to author LFO descriptors inline (per-section modulation), but that's out of scope.
- `Curve` is a simple enum: `.linear`, `.ease(.in/.out/.inOut)`, `.exponential(Double)`, `.custom([ControlPoint])`. Only `.linear` needs to ship for Phase 3; the rest can land incrementally.

## Out of scope

- MIDI CC output of modulation values to external gear (would need a new destination-writer path).
- Per-step modulator authoring (modulators are track- or cell-level; a "one LFO cycle starting at step N" would need a cell-specific shape).
- Cross-track modulation (one track's LFO modulating another track's parameter). Current routing is within-track.
- Tempo-synced rate modes for LFOs (rate = 1/4-note, 1/8-note, etc.). Would be a thin wrapper over Hz rate using `engineController.currentBPM`, but adds UI scope.
- Audio-rate LFOs for AU parameters without continuous-ramp support. Some AUs don't accept scheduled parameter writes; those fall back to tick-rate writes.
