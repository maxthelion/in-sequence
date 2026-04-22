# Source Pipeline: Chaining and AU-MIDI Readiness Review

**Parent plan:** `docs/plans/2026-04-21-source-pipeline-refactor.md`
**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`
**Status:** Review only. No code changes proposed here — this document captures where the built source pipeline stands relative to two design questions the plan did not fully answer.

## Motivating question

A track has a generator attached. Conceptually the generator is a combo of **step generator + pitch expander**, analogous to gate + CV. For a drum track the step generator alone suffices, with the output note specified on the stage. Two questions follow:

1. Does the current model support **chaining** these devices?
2. Does it live up to the idea of building the actual generators as **AU MIDI units** in the future?

## Current shape (as built)

Implemented in `Sources/Document/GeneratedSourcePipeline.swift`, `GeneratorParams.swift`, `GeneratedSourceEvaluator.swift`.

- `GeneratedSourcePipeline = { trigger: TriggerStageNode?, content }`
- `content ∈ { melodic(pitches: [PitchStageNode], shape), drum(triggers: [VoiceTag: TriggerStageNode], shape), slice(sliceIndexes), template(id) }`
- `TriggerStageNode = .native(StepStage)` — enum wrapper, single case
- `PitchStageNode = .native(PitchStage)` — enum wrapper, single case
- `StepStage = { algo: StepAlgo, basePitch: Int }`
- `PitchStage = { algo: PitchAlgo, harmonicSidechain: HarmonicSidechainSource }`
- Evaluation: `evaluateStep(pipeline, stepIndex, clipChoices, chordContext, state, rng) -> [GeneratedNote]`
- Evaluation state: `GeneratedSourceEvaluationState = { lastPitchesByLane: [Int?] }`

## Q1 — Chaining

**Answer: No.**

- Exactly one `TriggerStageNode?` per pipeline. No way to put two trigger stages in series.
- For `melodic`/`poly`, `pitches: [PitchStageNode]` are **parallel lanes** fed from the same trigger seed. Each lane consumes the seed independently and emits its own notes. No lane feeds another.
- Single-lane serial composition (e.g. `randomInScale` then a quantizer or humanizer after it) is not expressible.
- This is consistent with the plan's explicit framing: "fixed stage slots: trigger, pitch, note shape". The plan delivered what it scoped — but the scope does not include chaining.

## Q2 — AU MIDI readiness

**Answer: Partially. Wrappers are AU-ready; the evaluation model is not.**

Where the design holds up:

- `TriggerStageNode.native(...)` and `PitchStageNode.native(...)` are enum wrappers explicitly intended to take additive cases such as `.auProcessor(...)` without a second model redesign. This is intact.
- The drum path (`[VoiceTag: TriggerStageNode]` with `StepStage.basePitch`) already matches the "trigger stage with output note specified" mental model. Replacing a drum trigger with an AU MIDI unit is the most natural near-term fit.

Where it does not:

- **Event model mismatch.** The evaluator is a per-step snapshot: one call in, a flat `[GeneratedNote]` out per step. An AU MIDI processor is an event stream with sample/tick timing, note-on/off pairs, CCs, and pitch bend. A snapshot-per-step API cannot faithfully host one.
- **State container too narrow.** `GeneratedSourceEvaluationState = { lastPitchesByLane }` carries only last-pitch memory. AU MIDI units hold opaque per-instance state (arp phase, held notes, LFOs, envelopes) that must persist across the render timeline. There is no per-stage state slot.
- **No port/connection concept for sidechains.** `HarmonicSidechainSource` is an enum resolved at `evaluateStep` time into ambient data. An AU expects MIDI arriving on a second input bus or parameter values, not a Swift-enum resolution at call time.
- **I/O schema is fixed.** `emittedSeeds` returns `[NoteSeed]` (pitch + voiceTag). An AU emits arbitrary timed MIDI events. Adapting an AU's output back into the seed/GeneratedNote schema loses timing and non-note events.

## Options

Two tradeoffs worth naming explicitly.

### Option A — Keep fixed slots, defer AU hosting

- Treat the current shape as the native "gate + CV" — one trigger plus one or more parallel pitch lanes — and accept that AU MIDI hosting is a later, larger refactor.
- Cost: a second model/runtime change when AU hosting becomes real. The enum wrappers preserve call sites but not the evaluation contract.
- Benefit: zero disruption now. Matches the plan's delivered scope.

### Option B — Reshape to an event-stream pipeline now

- Replace `NoteSeed`/`[GeneratedNote]` with timed MIDI events.
- Replace `evaluateStep(...) -> [GeneratedNote]` with `render(range, state) -> [TimedMIDIEvent]`.
- Introduce a small `Stage` abstraction (input events in, output events out, per-instance state) that both native stages and AU-hosted stages implement.
- Introduce explicit sidechain input ports instead of enum-resolved ambient context.
- Benefit: serial chaining and AU hosting both drop out of the same shape.
- Cost: meaningful refactor across evaluator, preview, and engine wiring. Document compatibility impact is large; the plan already committed to fresh-model-only, so that part is cheap, but the runtime work is not.

## Recommendation shape (undecided)

Pick based on the horizon for AU-as-stage:

- **Near-term AU ambition** → do Option B before more native stages or editor surface land on the current shape.
- **Distant AU ambition** → Option A; the enum wrappers are a good-enough placeholder and the cost of the eventual rewrite is bounded.

Drum tracks are the cleanest first AU host target under either option.

## Non-goals of this document

- No new model, type, or API proposals.
- No test plan. If Option B is chosen, a follow-up plan document should own that.
- No backward-compatibility analysis beyond noting that the fresh-model-only stance from the parent plan still applies.
