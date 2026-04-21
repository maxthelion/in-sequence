# Source Pipeline Refactor: Step Trigger + Pitch Expander + Future AU Stage Slots

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`
**Status:** Not started. Tag `v0.0.27-source-pipeline-refactor` at completion.

## Summary

Refactor generated track sources from a flat “generator params” object into a small, ordered source pipeline with explicit stage slots:

- **Trigger stage**: emits note seeds (default base pitch = middle C unless a stage says otherwise)
- **Pitch stage(s)**: expand or transform those seeds into actual note output
- **Note shape**: remains the shared velocity/gate/accent layer
- **Clip source**: stays a separate top-level source path, not forced into the generated pipeline

This first slice should go beyond the editor: it should update the **model and runtime core** so playback uses the new trigger→pitch pipeline, while still keeping the stage palette intentionally small. Inputs use a **primary note input + optional named sidechain inputs** model. The first implemented sidechain is **harmonic sidechain** for pitch expansion, with runtime support for `project chord context` and `clip-derived pitch pool`. The API and editor should be shaped so that a future `.auProcessor(...)` stage can replace either the trigger or pitch stage without redesigning the whole source model.

## Key Changes

### 1. Spec and north-star updates

- Update the north-star document so generated sources are described as a **pipeline**, not just `StepAlgo × PitchAlgo`.
- Keep the orthogonal split, but change the semantics:
  - `StepAlgo` means **trigger generation** (“when does a note seed fire?”)
  - `PitchAlgo` means **pitch expansion/transformation** (“given incoming note seeds, what pitches come out?”)
- Add the explicit rule that a pitch stage consumes:
  - one **primary note stream**
  - zero or more **named sidechains**, with v1 shipping only `harmonicSidechain`
- Update the source-language in the source/track spec so:
  - `clip` remains a direct source path
  - an attached generator becomes an attached **generated source pipeline**
- Update the inventory text so future AU MIDI processors are described as **stage replacements** in the source pipeline, not a separate special-case subsystem.

### 2. Document model and type changes

Introduce pipeline-shaped types under `Sources/Document/`:

- `struct GeneratedSourcePipeline`
- `struct StepStage`
- `struct PitchStage`
- `enum HarmonicSidechainSource`
- `struct NoteSeed` or equivalent small internal note-seed value
- lightweight stage-slot wrappers for future extensibility:
  - `enum TriggerStageNode { case native(StepStage) }`
  - `enum PitchStageNode { case native(PitchStage) }`

Do **not** add AU-backed stage cases yet. The wrappers exist so future `.auProcessor(...)` is additive.

Reshape `GeneratorParams` so melodic generators no longer store raw algos directly:

- `mono(trigger: TriggerStageNode, pitch: PitchStageNode, shape: NoteShape)`
- `poly(trigger: TriggerStageNode, pitches: [PitchStageNode], shape: NoteShape)`
- `drum(triggers: [VoiceTag: TriggerStageNode], shape: NoteShape)`
- `slice(trigger: TriggerStageNode, sliceIndexes: [Int])`

Within native stages:

- `StepStage` wraps `StepAlgo` plus `basePitch` (default `60`)
- `PitchStage` wraps `PitchAlgo` plus `harmonicSidechain`

`HarmonicSidechainSource` in v1:

- `.none`
- `.projectChordContext`
- `.clip(UUID)`

Do **not** support old document decode shims. This is fresh-model-only.

### 3. Runtime and evaluation changes

Add one shared evaluator used by both preview and playback:

- `GeneratedSourceEvaluator` or equivalent shared runtime helper
- Trigger phase:
  - evaluates `StepStage`
  - emits note seeds at `basePitch` with no harmonic meaning yet
- Pitch phase:
  - takes incoming seeds
  - expands/transforms them using `PitchAlgo`
  - may output zero, one, or multiple notes per input seed
  - may consult `harmonicSidechain`

Rules for v1 pitch-stage behavior:

- `manual` = replace seed pitch using the configured pool/pick mode
- `randomInScale` = expand seed into one scale-constrained output pitch
- `randomInChord` = requires harmonic sidechain if present; otherwise falls back to its local root/chord params
- `intervalProb` = chooses an interval relative to configured/root context, applied to the incoming seed
- `markov` = history-aware transformation of incoming seed stream
- `fromClipPitches` = uses clip-derived pitch pool as the pitch source
- `external` remains stubbed unless there is already a working external pitch pool path; if still stubbed, keep it explicit and documented

Runtime wiring:

- Replace the `EngineController` path that currently compiles generated sources into a monolithic note program with the new shared evaluator
- Keep the outer engine graph shape stable for this slice; this is an internal source-generation refactor, not a full engine graph rewrite
- First runtime sidechain support:
  - `project chord context`
  - `clip-derived pitch pool`
- Explicitly defer arbitrary track-to-track note sidechains until routing is block-native

### 4. Track source UI changes

Refactor the track source UI so it reads like a small ordered pipeline.

For **clip** source:
- show clip pool picker
- show clip editor/preview
- do not show generator tabs

For **generated** source:
- show ordered sections/cards:
  - `Trigger`
  - `Pitch` (or `Pitch Lane N` for poly)
  - `Notes`
- keep the current tab-like affordance if useful, but the labels and copy must make the pipeline order obvious
- `Trigger` editor edits `StepStage`
- `Pitch` editor edits `PitchStage`
- `Notes` preview renders post-expansion output from the shared evaluator, not a UI-only approximation

Pitch editor changes:
- relabel it as a pitch **expander/transform** rather than a pitch picker
- add sidechain chooser for `harmonicSidechain`
- v1 sidechain choices shown in UI:
  - `None`
  - `Chord Context`
  - compatible clip choices

Poly editing:
- keep pitch lanes for `poly`, but each lane is explicitly a pitch stage fed from the same trigger stage
- lane add/remove remains, but the mental model becomes “multiple pitch processors over one trigger stream”

## Test Plan

- **Document/model**
  - `GeneratorParams` round-trip with new stage wrappers
  - defaults produce valid trigger/pitch stage objects
  - `HarmonicSidechainSource` round-trips
- **Evaluator**
  - middle-C trigger seeds expanded by `randomInScale` never leave the configured scale/range
  - `randomInChord` changes behavior when fed `project chord context`
  - `fromClipPitches` uses the referenced clip’s pitch pool
  - poly generator with two pitch lanes outputs both lanes’ notes
  - drum generator remains trigger-only; no pitch stage introduced there
- **Preview/UI parity**
  - `GeneratedNotesPreview` uses the shared evaluator, not a forked preview algorithm
  - one deterministic fixture proves preview and runtime agree for a seeded mono case
- **Engine**
  - selected generated source produces note events through the new pipeline
  - chord context changes output pitches on subsequent prepared steps
  - clip source playback is unchanged by this refactor
- **Manual smoke**
  - create a mono track, attach a generated source, set trigger to manual at 16th notes, set pitch expander to scale mode, confirm audible non-C output
  - set harmonic sidechain to chord context and change the chord source, confirm generated pitches respond
  - switch source to clip, confirm clip editor still appears and generated-source panels disappear

## Assumptions and defaults

- This is **not** a full arbitrary-stage pipeline in v1. It is a **pipeline-shaped source model** with fixed stage slots: trigger, pitch, note shape.
- `clip` remains a top-level direct source path. It is not forced into the generated-stage chain in this first pass.
- Side inputs use **primary + named sidechain** semantics, not arbitrary N-input graphs.
- V1 runtime sidechains are limited to:
  - `project chord context`
  - `clip-derived harmonic pool`
- Arbitrary track-output sidechains are intentionally deferred until routing becomes properly block-native.
- No backward compatibility work for old generator documents is included.
- Future AU MIDI processors will be added by introducing `.auProcessor(...)` cases to the stage-slot wrappers, not by redesigning the source editor or source model again.
