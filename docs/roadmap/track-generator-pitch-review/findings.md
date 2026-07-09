# Track Generator Pitch Review Findings

Date: 2026-07-07
Author: Codex
Status: implemented in generator source/bake repair, 2026-07-07

## Summary

Track generator trigger editing and playback are partially wired, but pitch-stage playback is not being applied for a generator used directly as a pattern-slot source.

The user-visible symptom matches the code path:

- Changing Euclidean trigger settings changes which steps fire.
- Changing generator Pitch-tab settings can appear to do little or nothing during playback.
- The preview/result strip may still show pitch-stage output, which makes the issue more confusing because preview and live playback can diverge.

The likely primary bug family is the source/modifier model around `.generator(...)` slots. The engine source path calls `GeneratedSourceEvaluator.evaluateSourceStep(...)`, which emits trigger seeds with `StepStage.basePitch`, then relies on `modifierGeneratorID` to run pitch processing. In many authored slots `SourceRef.generator(id)` sets `modifierGeneratorID` to that same generator id, so pitch can appear to work only because the source generator is also installed as its own modifier. If that retained modifier link is missing, bypassed, stale, or carried into a baked clip at the wrong time, pitch and bake behavior diverge from what the UI implies.

## Outcome

The repair changed generator-source playback to evaluate the full source
pipeline directly with `GeneratedSourceEvaluator.evaluateStep(...)`. The source
generator's Pitch tab is now audible without depending on
`modifierGeneratorID == generatorID`, and the legacy self-modifier link is
treated as compatibility state rather than a second processing pass.

Bake now uses a dedicated document conversion helper. The baked slot switches to
clip mode, points at the new concrete clip, retains the generator id for
switch-back/reuse, and clears an accidental self-modifier relationship while
preserving bypassed separate modifiers. Active separate modifiers are consumed
into the baked notes and not left live on the baked clip, avoiding a second
post-bake processing pass.

`GeneratedSourceEvaluationState` now carries role-scoped pitch memory for
generator source and generator modifier roles, keyed by pattern slot and
generator id. Source state is mirrored into the legacy lane for existing
precompute/fallback continuity rails; modifier state does not share that lane.

## Additional User Finding: Baked Clip Does Not Play

User report, 2026-07-07:

- Pressing the generator Bake button turns the generator into a clip.
- The resulting clip appears to exist.
- The clip does not play.
- Randomizing that same clip moves steps around visually, but still does not make it play.
- The user suspects something may need shifting over in the pattern.

This looks related to the same source/modifier/pattern-slot boundary rather than to clip randomization itself. `ClipRandomizeBaker` rewrites note-grid density, pitch, velocity, and gate data; it does not control which pattern slot the phrase plays, and it does not change source routing.

## Confirmed Code Path

Architecture docs currently say generator runtime evaluation is:

1. trigger stage emits note seeds;
2. pitch stage expands/transforms seeds;
3. note shape applies velocity/gate.

Relevant stable docs:

- `wiki/pages/generator-algos.md`
- `wiki/pages/playback-data-path.md`

The document evaluator has both pieces:

- `GeneratedSourceEvaluator.evaluateSourceStep(...)` emits source/seed notes from trigger stages.
- `GeneratedSourceEvaluator.processSourceNotes(...)` applies pitch-stage transformations to source notes.
- `GeneratedSourceEvaluator.evaluateStep(for params: ...)` does both by calling source evaluation and then processing.
- `GeneratedSourceEvaluator.previewNotes(for params: ...)` routes through `params.generatedSourcePipeline`, which applies pitch stages.

The live engine path does something narrower:

- `Sources/Engine/EngineController.swift`
- `EngineController.resolvedStepNotes(...)`
- `.generator(generatorID, modifierGeneratorID, modifierBypassed)` branch

Current behavior in that branch:

1. Look up source generator.
2. Call `GeneratedSourceEvaluator.evaluateSourceStep(for: generator.params, ...)`.
3. If there is no separate modifier generator, return those source notes.
4. If there is a modifier generator, run `processSourceNotes(... through: processor.params ...)`.

That means the source generator's own `PitchStageNode` is not applied by the source step itself. It is applied only if the slot has an active compatible `modifierGeneratorID`. Today `SourceRef.generator(id)` defaults that modifier id to the same `id`, which hides the split but makes the semantics fragile.

## Why The Step Part Works

`evaluateSourceStep(...)` does use the source generator's trigger stage. For mono/poly generators it calls `emittedSeeds(...)`, which checks the configured `StepAlgo`. This is why Euclidean pulse/step changes can affect playback.

The emitted notes still carry a pitch, but that pitch is only the trigger stage's `basePitch`. It is not the output of the Pitch tab.

## Why The Pitch Part Looks Broken

For a standalone mono/poly generator source, the Pitch tab updates `GeneratorParams.mono(... pitch: ...)` or `GeneratorParams.poly(... pitches: ...)`.

The preview strip uses:

- `GeneratorResultStrip.barContent(...)`
- `GeneratedSourceEvaluator.previewNotes(for: params, ...)`

That path applies pitch stages.

Playback uses:

- `EngineController.resolvedStepNotes(...)`
- `GeneratedSourceEvaluator.evaluateSourceStep(...)`

That path does not apply the source generator's pitch stages before returning unless an active modifier generator is present. In common cases the modifier generator may be the same UUID as the source generator, but that is an implicit shortcut rather than a clear source-pipeline contract. This creates room for preview/playback and bake/playback splits.

## Bake Path Findings

The Bake button routes through:

- `TrackSourceEditorView.bakeGeneratorToClip()`
- `SequencerDocumentSession.bakeGeneratorToClip(trackID:slotIndex:)`

Current bake behavior:

1. Reads the selected slot's `sourceRef.generatorID`.
2. Evaluates `GeneratedSourceEvaluator.previewNotes(for: generator.params, ...)` for 16 steps.
3. Converts each preview step into `ClipContent.noteGrid(lengthSteps: 16, steps: ...)`.
4. Calls `createBlankClipSource(trackID:slotIndex:)`.
5. Mutates the new clip content to the baked note grid.

Important details:

- Bake freezes the preview path, not the live playback path.
- `createBlankClipSource(...)` goes through the generic clip-source assignment path.
- `Project.setPatternClipID(...)` intentionally preserves `generatorID`, `modifierGeneratorID`, and `modifierBypassed` so bypassed generator slots can later re-engage their generator.
- Therefore a baked clip can inherit the generator/modifier relationship from the generator slot it came from.

That preservation is useful for bypass/unbypass, but bake has different product semantics: the user expects a one-way conversion from generated output into a playable clip. A baked clip probably should not accidentally depend on a retained source/modifier relationship unless we intentionally expose that as "bake source but keep modifier."

## Why Randomize Did Not Help

Randomizing the baked clip can move notes inside the clip but still not produce sound if the issue is outside the clip content.

Likely non-content causes:

- The phrase Pattern layer is not currently resolving playback to the baked slot.
- The baked clip inherited an active modifier relationship that changes or invalidates the playback path.
- The engine briefly installed a snapshot with a blank clip before the second mutation filled the clip.
- The user-visible editor selected slot is based on `selectedPhrase.patternIndex(... stepIndex: 0)`, while playback can resolve a different pattern index on other steps if the Pattern layer is per-step, per-bar, inherited, or automated.

The pattern-slot hypothesis is especially consistent with "randomize moved steps around but did not make it play": randomize changes the selected clip's contents, but it does not change the phrase's pattern-index cells.

## Adjacent Risks To Review Holistically

### Source Generator vs Modifier Generator Semantics

The current code treats a generator-source slot as if its generator only produces raw source notes, and treats modifier generators as the only pitch-processing stage.

That conflicts with the model in `GeneratorParams`, where mono/poly source generators already contain both trigger and pitch stages. A holistic fix should clarify:

- Source generator means full generator pipeline: trigger plus its own pitch stage.
- Modifier generator means an optional second processing pass over source notes.
- Clip source plus modifier generator continues to use modifier processing over clip notes.
- Bake means freeze the audible source result into clip content, with an explicit decision about whether the modifier remains attached or is consumed into the baked notes.

### Double Processing Risk

The obvious fix is not just "always call `evaluateStep` and then run the modifier." If the source is evaluated through the full source generator pipeline and then a modifier is applied, that is probably correct, but it changes the current behavior for generator-source slots with modifiers.

That behavior should be explicitly tested:

- source generator pitch stage applies first;
- modifier generator pitch stage applies second;
- bypassing modifier leaves source generator pitch intact;
- clip source modifier behavior remains unchanged.

### Stateful Pitch Algorithms

Pitch algorithms such as Markov and pool memory use `GeneratedSourceEvaluationState`. Today the engine passes one state object into `processSourceNotes(...)`.

A fix must preserve state continuity for:

- source generator pitch state;
- modifier generator pitch state;
- poly generator lane state;
- precompute bar equivalence.

There may be a modeling gap here: one `GeneratedSourceEvaluationState` per track may not be enough if source and modifier both have independent stateful pitch stages. At minimum, tests should pin the intended behavior before changing it.

### Preview vs Playback Drift

Preview currently appears closer to the intended semantics than playback. The result strip uses `previewNotes(...)`, while live playback uses the narrower source-step path.

Any fix should add a test that the preview/result-strip evaluation and `EngineController.resolvedStepNotes(...)` agree for deterministic generator settings.

### Bake vs Playback Drift

Bake currently freezes preview evaluation into a clip. If preview and playback differ, bake can produce a clip that visually matches the strip while live playback did not. Conversely, after bake, live playback may still be affected by phrase slot selection and retained modifier state.

The bake contract should be pinned:

- What you hear from the generator before bake should match what the baked clip plays after bake, for deterministic generators.
- The selected phrase/pattern state should keep playback pointed at the baked clip, or the UI should make it explicit when it does not.
- The resulting clip source should have intentional modifier state, not whatever happened to be retained for bypass.

### Documentation Drift

`wiki/pages/playback-data-path.md` currently says the generator source path calls `evaluateSourceStep(...)`, then says `GeneratedSourceEvaluator` owns trigger stages and pitch stages. That is ambiguous enough to hide this bug.

Once the fix lands, update the wiki to make the source/modifier split explicit.

## Suggested Regression Tests

Add engine-boundary tests, not only document-evaluator tests. Existing document tests already prove `GeneratedSourceEvaluator.evaluateStep(...)` can apply pitch stages, so they do not catch the playback bug.

Recommended tests:

1. Generator source playback applies its own manual pitch stage.
   - Create a generator with Euclidean trigger firing every step.
   - Set trigger `basePitch` to 60.
   - Set pitch stage to manual `[72]`.
   - Assert `EngineController.resolvedStepNotes(...)` emits pitch 72, not 60.

2. Generator source playback matches deterministic preview.
   - Use a deterministic manual pitch sequence.
   - Compare `GeneratedSourceEvaluator.previewNotes(...)` with engine-resolved notes over one bar.

3. Modifier bypass does not bypass source generator pitch.
   - Attach a modifier generator but set `modifierBypassed = true`.
   - Assert source generator pitch stage still applies.

4. Source plus modifier applies in a defined order.
   - Use source manual pitch `[64]`.
   - Use modifier manual pitch `[67]` or a transposition-like deterministic stage if available.
   - Assert the intended final pitch.

5. Clip plus modifier remains unchanged.
   - Protect the existing clip modifier path from regression.

6. Stateful pitch continuity remains stable.
   - Use a stateful pitch algo or deterministic memory-sensitive setup.
   - Assert live per-step and precompute paths match.

7. Bake creates a playable clip on the audible slot.
   - Set up a generator-backed selected slot that emits deterministic notes.
   - Call `bakeGeneratorToClip(trackID:slotIndex:)`.
   - Assert the slot is in clip mode and points to the new clip.
   - Assert `EngineController.resolvedStepNotes(...)` emits the baked notes.

8. Bake handles retained modifier state intentionally.
   - Start with a generator source whose `modifierGeneratorID` equals its `generatorID`.
   - Bake to clip.
   - Assert the resulting source ref either has no active modifier, or assert the explicitly chosen "keep modifier" semantics.

9. Bake and Pattern layer selection stay aligned.
   - Use a phrase whose Pattern layer resolves to the baked slot at step 0 and to other slots on later steps.
   - Assert playback behavior is documented and visible: either only step-0 slot playback changes, or bake/global-apply updates the intended phrase pattern cells.

10. Randomize-after-bake changes audible playback when the baked slot is active.
    - Bake a generator to a clip.
    - Randomize that clip.
    - Assert resolved playback changes on steps where the phrase selects that slot.

## Candidate Fix Shape

Preferred shape:

- Add a helper to evaluate a generator source as a complete source pipeline.
- Use that helper in `EngineController.resolvedStepNotes(...)` for `.generator(...)` slots.
- Then optionally pass those already-realized source notes through a separate modifier generator when present and not bypassed.
- Give bake a dedicated conversion path instead of reusing generic clip assignment blindly.
- Decide whether bake consumes source modifiers into the resulting clip or preserves them as an explicit post-bake modifier.

Possible helper:

```swift
GeneratedSourceEvaluator.evaluateStep(
    for: generator.params,
    stepIndex: resolved.sourceStepIndex,
    clipChoices: playbackSnapshot.clipPool,
    chordContext: chordContext,
    state: &sourceState,
    rng: &rng
)
```

Open design point: state storage. If source and modifier can both be stateful, the engine likely needs a way to avoid source and modifier stages sharing a single lane-state namespace accidentally.

## Files To Touch For A Fix

Likely:

- `Sources/Engine/EngineController.swift`
- `Sources/Document/GeneratedSourceEvaluator.swift` if a clearer helper is introduced
- `Sources/App/SequencerDocumentSession+TrackSourceSlotModifiers.swift`
- `Sources/Document/Project+TrackSources.swift`
- `Tests/SequencerAITests/Engine/PlaybackSnapshotBuffersOnlyTests.swift` or a new focused engine test file
- a new app/session test for `bakeGeneratorToClip(...)`
- `wiki/pages/playback-data-path.md`
- potentially `wiki/pages/generator-algos.md`

Possibly:

- `Sources/Engine/BarPrecompute.swift`
- `Sources/Engine/TickStateBuffer.swift`
- `Sources/Engine/BarPrecomputeScheduler.swift`

Those become relevant if the state model needs to distinguish source-generator state from modifier-generator state.

## Recommendation

Treat this as a source/modifier semantics cleanup rather than a one-line pitch fix.

The smallest safe milestone is:

1. Add failing engine-boundary tests for standalone generator pitch playback.
2. Fix standalone generator-source playback to use the full source pipeline.
3. Add preview-vs-playback equivalence for deterministic generator sources.
4. Add bake-to-playback equivalence for deterministic generator sources.
5. Decide and test whether bake consumes or preserves modifier state.
6. Then handle generator-source-plus-modifier semantics explicitly, with tests, before broadening the change to stateful pitch algorithms.
