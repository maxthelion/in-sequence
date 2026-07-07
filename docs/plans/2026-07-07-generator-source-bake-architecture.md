# Goal: Generator Source, Modifier, and Bake Architecture Repair

Status: implemented; automated verification complete; manual smoke not run
Created: 2026-07-07
Checkout: `/Users/maxwilliams/dev/in-sequence`

## Objective

Repair generator playback and bake semantics so a pattern slot has clear,
testable source behavior:

- a generator source evaluates as a complete pipeline: trigger -> pitch -> shape;
- a modifier generator is an optional extra note processor, not how a source
  generator's Pitch tab works;
- baking freezes the audible generator result into a playable clip;
- baking preserves the generator recipe so the user can return to live
  generation or reuse the generator elsewhere;
- preview, live playback, and baked clip playback agree for deterministic
  generators.

This goal exists because generator pitch and generator bake currently depend on
an implicit self-modifier relationship. That makes Euclidean trigger edits
mostly work while pitch edits and baked clips can diverge from what the UI
implies.

Primary investigation artifact:

- `docs/roadmap/track-generator-pitch-review/findings.md`

Related architecture context:

- `wiki/pages/generator-algos.md`
- `wiki/pages/playback-data-path.md`
- `docs/plans/2026-04-21-source-pipeline-refactor.md`

## Non-Negotiable Product Semantics

### Pattern Slot Sources

A pattern slot may retain both authored source options:

- retained generator source: `generatorID`
- retained clip source: `clipID`

Only one is active:

- active mode `.generator`: play the retained generator source;
- active mode `.clip`: play the retained clip source.

Retaining `generatorID` while active mode is `.clip` is desired. It allows:

- returning the same pattern to live generation after bake;
- preserving generator settings;
- reusing or reapplying the generator recipe.

### Generator Source

A generator source is a full generated-source pipeline:

```text
TriggerStage -> PitchStage(s) -> NoteShape -> [GeneratedNote]
```

The source generator's own pitch stages must run even when no modifier generator
is attached.

### Modifier Generator

A modifier generator is optional and separate:

```text
Source notes -> Modifier PitchStage(s) -> [GeneratedNote]
```

Modifier state must not be required for source-generator pitch to work.

### Bake

Bake is non-destructive to the generator recipe but destructive to ambiguity:

- create/update a concrete clip from the audible generator result;
- switch the slot's active mode to `.clip`;
- point `clipID` at the baked clip;
- preserve `generatorID` and the unchanged generator pool entry;
- leave modifier state in an explicit, tested state.

Default target behavior for this goal:

- after bake, the baked clip plays by itself;
- the retained `generatorID` remains available for switching back to live
  generator mode;
- an accidentally self-referential source-as-modifier link must not remain
  active on the baked clip.

If product/design later wants "bake source only, keep modifier live", add that
as an explicit UI mode. Do not preserve it accidentally.

## Scope

In scope:

- document/engine semantics for generator source evaluation;
- source/modifier state separation where needed for deterministic behavior;
- bake-to-clip session behavior;
- regression tests for generator playback, bake, modifier preservation, and
  randomize-after-bake;
- wiki updates to remove ambiguous source/modifier language.

Out of scope:

- new generator algorithms;
- arbitrary AU-backed trigger/pitch stages;
- broad UI redesign of the generator editor;
- changing how clip editing works beyond bake/randomize interaction tests;
- removing the ability to retain generator settings after bake.

## Files Likely To Touch

Likely source files:

- `Sources/Document/TrackSourceCatalog.swift`
- `Sources/Document/Project+TrackSources.swift`
- `Sources/Document/GeneratedSourceEvaluator.swift`
- `Sources/Engine/EngineController.swift`
- `Sources/Engine/BarPrecompute.swift`
- `Sources/Engine/TickStateBuffer.swift`
- `Sources/Engine/BarPrecomputeScheduler.swift`
- `Sources/App/SequencerDocumentSession+TrackSourceSlotModifiers.swift`
- `Sources/UI/TrackSource/TrackSourceEditorView.swift` only if UI state needs a
  small affordance or status update

Likely tests:

- `Tests/SequencerAITests/Document/SourceRefNormalizationTests.swift`
- `Tests/SequencerAITests/Document/ProjectSetPatternClipIDTests.swift`
- new `Tests/SequencerAITests/Engine/GeneratorSourcePlaybackTests.swift`
- new `Tests/SequencerAITests/App/GeneratorBakeSessionTests.swift`
- existing precompute/state-continuity tests if state storage changes

Docs:

- `wiki/pages/playback-data-path.md`
- `wiki/pages/generator-algos.md`
- optionally append outcome notes to
  `docs/roadmap/track-generator-pitch-review/findings.md`

## Execution Plan

### Task 1: Characterize Current SourceRef Semantics

Goal: Make the current implicit self-modifier behavior visible in tests before
changing it.

- [x] Add a document-level characterization proving `SourceRef.generator(id)`
      currently sets both `generatorID` and `modifierGeneratorID`.
- [x] Add a document-level characterization proving clip mode may retain
      `generatorID` for switch-back.
- [x] Add a characterization for `Project.setPatternClipID(...)` showing which
      fields survive clip assignment today.
- [x] Run the focused document tests and record the pre-fix behavior in the
      commit message or plan notes.

Expected result: tests describe the old behavior clearly enough that later edits
can distinguish intentional retention from accidental active modifier leakage.

### Task 2: Add Engine Boundary Regression Tests For Generator Source Playback

Goal: Pin the user-facing pitch bug at the engine boundary.

- [x] Create a deterministic generator-backed track fixture.
- [x] Test standalone generator source playback applies its own manual pitch
      stage.
      - trigger base pitch: `60`
      - pitch stage: manual `[72]`
      - expected engine notes: `[72]`, not `[60]`
- [x] Test generator preview output equals
      `EngineController.resolvedStepNotes(...)` over one deterministic bar.
- [x] Test modifier bypass does not bypass the source generator's own pitch.
- [x] Test clip-source playback is unchanged by the new generator-source
      behavior.

Expected result before fix: at least the standalone source pitch test should
fail honestly.

### Task 3: Make Generator Source Evaluation Complete

Goal: Change `.generator(...)` slot playback so source generator pitch is not a
modifier side effect.

- [x] Introduce or reuse a helper that evaluates a source generator as a full
      pipeline:

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

- [x] Update `EngineController.resolvedStepNotes(...)` so `.generator(...)`
      uses full source evaluation before optional modifier processing.
- [x] Preserve drum/progression/slice behavior.
- [x] Preserve clip source behavior.
- [x] Run the new focused engine tests.

Important: do not solve this by relying on `modifierGeneratorID == generatorID`.
That shortcut is the architecture bug.

### Task 4: Separate Source And Modifier Evaluation State

Goal: Avoid source and modifier pitch stages sharing state accidentally.

- [x] Audit current `GeneratedSourceEvaluationState` storage and all call sites.
- [x] Decide the smallest state keying model that separates source and modifier
      state. Candidate:

      ```text
      trackID + slotIndex + generatorID + role(source|modifier)
      ```

- [x] Update tick/precompute state plumbing only as far as needed.
- [x] Add a stateful regression using scoped source/modifier pitch memory.
- [x] Run existing precompute state-continuity tests.

If a full state-key refactor is too large, record that explicitly and add a
temporary test-pin for the current single-state behavior. Do not leave silent
state sharing undocumented.

### Task 5: Define And Implement Bake Conversion Semantics

Goal: Bake creates a playable clip while preserving generator settings for
switch-back/reuse.

- [x] Add a dedicated bake conversion helper instead of relying on generic
      `createBlankClipSource(...)` semantics alone.
- [x] Bake from the same deterministic source evaluation that live playback uses.
- [x] Create or update the baked clip in one coherent session mutation so the
      engine does not receive a meaningful intermediate "blank clip" snapshot.
- [x] Switch the slot to `.clip`.
- [x] Set `clipID` to the baked clip.
- [x] Preserve `generatorID` and the generator pool entry unchanged.
- [x] Clear or bypass any self-modifier relationship that only existed to make
      source pitch work.
- [x] Preserve a genuinely separate user-selected modifier only if this goal
      explicitly chooses that behavior and tests it.

Default implementation target:

```text
after bake:
  mode = .clip
  clipID = bakedClipID
  generatorID = previousGeneratorID
  modifierGeneratorID = nil OR explicitly bypassed if it was the previous source generator
```

If the pre-existing modifier was a different generator selected by the user,
pause long enough to make an intentional choice in code and tests. The likely
safe default is to keep it only when it is not the source generator.

### Task 6: Add Bake And Randomize Regression Tests

Goal: Pin the exact user-reported bake failure and the randomize follow-up.

- [x] Test `bakeGeneratorToClip(trackID:slotIndex:)` creates a clip with note
      data matching deterministic generator playback.
- [x] Test the baked slot resolves through `EngineController.resolvedStepNotes`
      as audible clip notes.
- [x] Test generator settings remain available after bake:
      - `generatorID` still present on the slot;
      - generator pool entry unchanged;
      - switching active mode back to generator restores live generation.
- [x] Test baked clip does not accidentally depend on source-as-modifier state.
- [x] Test randomize-after-bake changes audible playback when the phrase
      Pattern layer selects the baked slot.
- [x] Test a phrase whose Pattern layer selects other slots remains honest:
      randomizing the baked slot should not be expected to change steps that do
      not resolve to that slot.

### Task 7: Update UI/Status Only If Needed

Goal: Make existing controls reflect the corrected semantics without a redesign.

- [x] Verify the Bake button still appears only when a generator source is active
      and bake is meaningful.
- [x] Verify the slot/source UI still lets a user switch back to the retained
      generator after bake.
- [x] If modifier state changes visibly, ensure the UI does not show a stale
      active modifier after bake.
- [x] If pattern-slot selection is still a likely confusion point, add a compact
      status or tooltip only if it fits the existing UX canon.

Run `scripts/diagnostics/ux-canon-lint.sh` if any `Sources/UI` files change.

### Task 8: Documentation And Wiki

Goal: Leave durable semantics behind so this does not regress.

- [x] Update `wiki/pages/playback-data-path.md`:
      - generator source path uses full source pipeline;
      - modifier path is optional and second-stage;
      - bake preserves recipe but plays concrete clip.
- [x] Update `wiki/pages/generator-algos.md` if it still implies runtime parity
      without the source/modifier split.
- [x] Append outcome notes to
      `docs/roadmap/track-generator-pitch-review/findings.md`.

### Task 9: Verification

Required focused checks:

- [x] document tests touching `SourceRef` / pattern source behavior;
- [x] new generator source playback tests;
- [x] new bake session tests;
- [x] precompute/state-continuity tests if state plumbing changes.

Required broad checks when implementation touches engine playback:

- [x] relevant `xcodebuild test` subset for `SequencerAITests`;
- [x] `scripts/diagnostics/realtime-path-lint.sh` if tick/audio-path files
      changed;
- [x] `scripts/diagnostics/runtime-ownership-lint.sh` if engine/runtime
      ownership boundaries changed;
- [x] `scripts/diagnostics/ux-canon-lint.sh` if UI files changed.

Manual smoke:

- [ ] Create or select a mono generator pattern.
- [ ] Set Euclidean trigger to a sparse pattern and Pitch tab to a clearly
      non-default manual pitch.
- [ ] Confirm preview and playback match.
- [ ] Bake to clip.
- [ ] Confirm the baked clip plays.
- [ ] Randomize the baked clip while the phrase selects that slot; confirm
      audible pattern changes.
- [ ] Switch back to generator mode; confirm the previous generator settings are
      still present and live playback resumes from the recipe.

Manual smoke was not run in this pass. The same semantics are covered by
engine/session tests: deterministic generator playback matches preview, bake
creates audible clip notes, randomize-after-bake changes playback when the
baked slot is selected, other Pattern slots remain unchanged, and switching
the slot back to generator mode restores the retained recipe.

## Implementation Outcome

Completed on 2026-07-07:

- `EngineController.resolvedStepNotes(...)` now evaluates generator sources with
  the full source pipeline before optional modifier processing.
- Legacy self-modifier links are ignored as extra processors, so old
  `SourceRef.generator(id)` state does not double-process.
- `GeneratedSourceEvaluationState` now has role-scoped source/modifier lanes;
  source state mirrors to the legacy lane for precompute/fallback continuity.
- Bake uses `Project.bakeGeneratorSourceToClip(...)` in a single session batch,
  switches the active slot to clip, retains the generator recipe, clears
  self-modifier state, preserves bypassed separate modifiers, and clears active
  separate modifiers after freezing their audible result into the baked clip.
- Regression tests cover generator pitch, preview/playback parity, modifier
  bypass, slot-scoped source/modifier state separation, live-path bake with chord
  context, inactive retained-generator bake guards, switch-back, and
  randomize-after-bake authored Pattern-layer behavior.

Verification passed:

- `GeneratorSourcePlaybackTests`
- `GeneratorBakeSessionTests`
- `SourceRefNormalizationTests`
- `ProjectSetPatternClipIDTests`
- `ProjectSelectedSlotSourceHelpersTests`
- `PrecomputeStateContinuityTests`
- `PrecomputeBarEquivalenceTests`
- app build
- `scripts/diagnostics/realtime-path-lint.sh`
- `scripts/diagnostics/runtime-ownership-lint.sh`
- `scripts/diagnostics/ux-canon-lint.sh`

## Acceptance Criteria

- A standalone generator source no longer needs `modifierGeneratorID` for its
  own Pitch tab to affect playback.
- Deterministic generator preview equals deterministic generator playback.
- Deterministic bake output equals deterministic generator playback before bake.
- Baked clips are playable as clips.
- Generator settings survive bake and can be reactivated.
- Randomize-after-bake affects audible playback when the baked slot is selected.
- Clip-source plus genuine modifier behavior remains covered by tests.
- Any retained modifier state after bake is intentional and tested.
- Documentation describes source, modifier, clip, and bake semantics without
  relying on implicit self-modifier behavior.

## Risks And Guardrails

- Do not remove generator retention after bake. The user explicitly wants to keep
  generator settings.
- Do not hide the bug by disabling the Pitch tab, bypassing modifiers globally,
  or special-casing preview only.
- Do not weaken audio hard rules. Generator evaluation remains off render
  threads and must respect existing precompute/lookahead boundaries.
- Be careful with stateful pitch algorithms. Preview/playback equivalence for
  deterministic cases is necessary but not sufficient for Markov/memory
  behavior.
- Existing documents may have source generator ids duplicated into
  `modifierGeneratorID`; migration/normalization should treat that as old
  self-modifier semantics, not as proof the user intentionally selected a
  separate modifier.

## Suggested Commit Slices

1. Characterization and failing engine/bake tests.
2. Generator source evaluation fix.
3. Source/modifier state separation, if needed.
4. Bake conversion semantics and session tests.
5. Docs/wiki updates.
