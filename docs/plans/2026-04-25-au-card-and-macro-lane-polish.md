# AU Destination Card & Per-Step Clip Macro Lanes — Port from max-8

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`
**Reference branch:** `codex/max-8-destination-au` — original implementation, authored against the pre-v2 mutation API. **Do not cherry-pick from it.** Read each commit's diff for design intent; re-author against `LiveSequencerStore`'s typed API.
**Status:** Not started. Tag `v0.0.NN-au-card-and-macro-lanes` at completion.

## Why this plan exists

`codex/max-8-destination-au` had ten commits of UI polish + a substantial new feature (per-step clip macro lanes). One commit landed via FF merge as `18d8b73` (the AU editor card redesign). The remaining nine were authored against the pre-v2 mutation API (`session.mutateProject(impact:)`, `project.addAUMacro(...)`, etc.) — APIs that no longer exist on main after `LiveSequencerStore` v2 took over. A direct cherry-pick would force per-commit re-targeting at the API layer, not just conflict resolution; it produced a tangled, partially-rewritten history when attempted earlier this session and was aborted.

The work itself remains worth landing. This plan ports the design intent to v2-shape code as a sequence of tight, reviewable commits.

## Scope: in

The nine unmerged commits, grouped by theme:

| Reference commit | Intent |
|---|---|
| `e2030f8 fix(au-presets): avoid preset browser layout deadlock` | Preset browser hangs when a sheet's reactive size loop wedges layout. |
| `24eda8b fix(document): keep macro layers when adding drum groups` | Adding a drum group dropped the per-track macro layer entries. |
| `c06fb20 feat(au): simplify destination macro controls` | Replace `auMacroGrid` + `DestinationMacroKnob` with `auMacroSlots: [AUMacroSlot]` + `AUMacroSlotKnob` — fixed-width slot row instead of an adaptive grid. |
| `a91cc15 feat(au): step presets inline` | New `PresetStepper` view: prev/next preset buttons inline on the destination card, replacing the modal-only browser path. |
| `9d808ee feat(sample): restyle sampler destination card` | Restyle of `SamplerDestinationWidget` to match the new AU card aesthetic; touches `SamplerSettings` (gain remapping cleanup) and `SamplePlaybackEngine` (test surface). |
| `45f9663 fix(au): fit destination card in side column` | Layout fix: cards overflowed the inspector column at narrower widths. |
| `bf85314 fix(ui): keep destination beside source` | Layout fix: destination panel was drifting below the source panel on certain widths. |
| `5f507ea fix(ui): keep track page interactive after sample restyle` | Regression fix from the sampler restyle: pointer events were getting eaten in the new card layout. |
| `a01eeb5 feat(clip): add per-step macro lane slots` | The big one. Per-step override lane in clips, exposed as a strip of "macro slots" (M1, M2, …) that bind specific macros to per-step values, layered on top of the phrase-layer default. New `SingleMacroSlotPickerSheet`. |

## Scope: out

- The AU editor card redesign (`93f931e` on max-8) — already on main as `18d8b73`. Not re-touching.
- Anything not on `codex/max-8-destination-au`. If the `cherry-mark` shows max-8 commits as already-equivalent on main, they are skipped here too.
- Audio-rate macro automation; per-voice macros; MIDI-CC binding for macro slots — all out of v1's macro plan and remain out here.

## Architecture

The big shift since max-8 was authored: the document model is a persistence DTO; live state lives in `LiveSequencerStore`; UI reads from `session.store.*` and writes via typed mutation methods on `SequencerDocumentSession`. Three concrete substitutions to keep front-of-mind:

| max-8 wrote | v2 equivalent |
|---|---|
| `session.mutateProject { project in project.X = Y }` | typed method on `SequencerDocumentSession` (e.g. `session.setEditedDestination`, `session.setMacroLayerDefault`, `session.setFilterSettings`, `session.writeStateBlob`) |
| `session.mutateProject(impact: .scopedRuntime(...)) { ... }` | one of the typed `set...` methods that already encodes the right `LiveMutationImpact` internally |
| `session.mutateProject { project in project.addAUMacro(...); project.syncMacroLayers() }` | `session.batch(impact: .snapshotOnly, changed: .full) { store in var p = store.exportToProject(); p.addAUMacro(...); p.syncMacroLayers(); store.replaceTracks(p.tracks); store.setLayers(p.layers); store.replacePhrases(p.phrases, selectedPhraseID: p.selectedPhraseID) }` (see `applyMacroDiff` in `SequencerDocumentSession+Mutations.swift` for the canonical pattern) |
| `session.project.X` | `session.store.X` (via `LiveSequencerStore+Accessors.swift`) |
| `MacroKnobRowViewModel().currentValue(..., project: session.project)` | `MacroKnobRowViewModel().currentValue(..., layers: session.store.layers)` |

For each task below, the implementer's loop is:
1. Read the reference commit on `codex/max-8-destination-au` end-to-end.
2. Identify the design intent (UI shape, data flow, behavioural change). Don't follow the diff line-by-line.
3. Re-author on a fresh branch off main, using v2's typed API. Tests come along, ported to assert against `session.store.*` rather than `session.project.*`.
4. Build and run the relevant unit tests. If a test in max-8 was a `mutateProject` snapshot test, update it to use a typed setter.

## Dependencies

- Main is at or after `bd92d8e` (i.e. `LiveSequencerStore` v2, the AU card redesign as `18d8b73`, the AU component cache fix as `ce2ccd4`).
- `codex/max-8-destination-au` exists locally and contains the reference SHAs above. Do not delete it until this plan is closed.

## File structure (post-plan)

```
Sources/Document/
  TrackMacroBinding.swift                         MODIFIED — slotIndex
  TrackMacroDescriptor.swift                      MODIFIED — slot bookkeeping
  ClipContent.swift                               MODIFIED — macroLanes per noteGrid
  StepSequenceTrack.swift                         MODIFIED — macro slot helpers
  Project+TrackMacros.swift                       MODIFIED — addAUMacro(slotIndex:), removeMacro(id:from:), syncMacroLayers ordering
  Project+DrumGroups.swift                        MODIFIED — preserve macro layers when adding a drum group

Sources/Engine/
  SequencerSnapshotCompiler.swift                 MODIFIED — clip macro lane resolution at step

Sources/UI/
  TrackDestinationEditor.swift                    MODIFIED — auMacroSlots / AUMacroSlotKnob; PresetStepper integration; layout
  TrackDestination/PresetStepper.swift            NEW — prev/next preset stepper
  TrackDestination/SingleMacroSlotPickerSheet.swift NEW — single-slot picker
  SamplerDestinationWidget.swift                  MODIFIED — restyle to match the new AU card aesthetic
  Track/ClipMacroLaneEditor.swift                 MODIFIED — embed in ClipContentPreview rather than standalone
  TrackSource/Clip/ClipContentPreview.swift       MODIFIED — macro slot strip + selected-binding lane
  TrackSource/TrackSourceEditorView.swift         MODIFIED — wire macroSlots / onAssignMacroSlot / onUpdateMacroLanes
  MacroKnobRow.swift                              MODIFIED — slotIndex-aware ordering

Sources/App/
  SequencerDocumentSession+Mutations.swift        MODIFIED (if needed) — additional typed methods uncovered while porting

Tests/SequencerAITests/
  Document/
    ProjectTrackMacroTests.swift                  MODIFIED — slotIndex assertions
    StepSequenceTrackFilterDefaultTests.swift     MODIFIED — macro slot defaults
    TrackMacroDescriptorTests.swift               MODIFIED — slotIndex round-trip
    ProjectAddDrumGroupTests.swift                MODIFIED — macro-layer preservation
  UI/
    PresetStepperTests.swift                      NEW — pure ViewModel test
```

## Task 1 — Bug fixes (preset deadlock + drum-group macro layers)

**Reference commits:** `e2030f8`, `24eda8b`. Both small.

**`e2030f8`:** preset browser layout deadlock. Read its diff to identify the offending fixed-size / `presentationDetents` / sheet sizing pattern. The fix is mechanical and applies the same on v2 (the deadlock is in SwiftUI layout, not session API).

**`24eda8b`:** `addDrumGroup` was discarding `project.layers` entries that referenced the new member tracks' macro IDs. Port the fix to `Project+DrumGroups.swift` (or wherever `addDrumGroup` now lives on main; check before modifying). If main's drum-group flow has changed since max-8 authored this, audit the current `addDrumGroup` implementation against the bug and re-author the fix to match the new shape.

**Tests:** port the assertions from max-8's added tests in `ProjectAddDrumGroupTests.swift`; update if the typed-API mutation path differs.

- [ ] Read `e2030f8` and `24eda8b` diffs end-to-end
- [ ] Implement preset-browser fix; manually smoke that opening the preset browser on an AU destination doesn't hang
- [ ] Implement drum-group macro layer preservation
- [ ] Tests green
- [ ] Commit: `fix(ui): preset browser sheet sizing deadlock`
- [ ] Commit: `fix(document): keep macro layers when adding drum groups`

## Task 2 — Replace auMacroGrid with auMacroSlots

**Reference commit:** `c06fb20 feat(au): simplify destination macro controls` (+263/-168 in `TrackDestinationEditor.swift`).

The AU card redesign that landed (`18d8b73`) put `auMacroGrid: some View` plus a `DestinationMacroKnob` view on the editor. `c06fb20` replaces the adaptive grid with a fixed-width slot row driven by `auMacroSlots: [AUMacroSlot]`, with `AUMacroSlotKnob` rendering each slot. Slot indices stabilise the row's layout so the user's muscle memory survives macro add/remove.

The slot model is a precondition for Task 6 (per-step macro lanes). It introduces `slotIndex` as a concept that the clip macro lanes need.

**Implementation:** read `c06fb20`'s diff for the new view shape. Drop `auMacroGrid` and `DestinationMacroKnob` from `TrackDestinationEditor.swift`. Add `AUMacroSlot`, `auMacroSlots`, `AUMacroSlotKnob`, and a `compactIconButton` helper if used. Wire the macro live-drag through `session.setMacroLayerDefault` (already typed on `SequencerDocumentSession+Mutations.swift:340`).

The `onRemove` per-slot path uses the `session.batch` pattern documented in the architecture table — `removeMacro(id:from:)` + `syncMacroLayers()` need to land in one batch.

**Tests:** none in `c06fb20` itself for this surface (matches repo convention: SwiftUI views are integration-tested manually).

- [ ] Read `c06fb20` diff
- [ ] Replace `auMacroGrid`/`DestinationMacroKnob` with `auMacroSlots`/`AUMacroSlotKnob`
- [ ] `auMacroBindings` becomes the source of slot data; introduce `slotIndex` ordering if not already on `TrackMacroBinding`
- [ ] Drag → `session.setMacroLayerDefault`
- [ ] Remove → `session.batch` with `removeMacro` + `syncMacroLayers`
- [ ] Build green
- [ ] Manual smoke: open an AU destination, drag a macro knob, watch the layer default update
- [ ] Commit: `feat(au): destination macro slot row`

## Task 3 — Step presets inline (PresetStepper)

**Reference commit:** `a91cc15 feat(au): step presets inline` (+191/-54 across `TrackDestinationEditor.swift`, new `PresetStepper.swift`, new `PresetStepperTests.swift`).

A small standalone view: prev / next buttons that step through factory + user presets returned by `engineController.presetReadout(for: trackID)`. Lives inline on the destination card so users don't have to open the modal browser for every preset change.

**Implementation:** lift the design from `a91cc15`. The view is pure — it takes a `PresetReadout`, the current preset id, and `onSelect: (AUPresetDescriptor) -> Void`. Wire the `onSelect` to the existing `engineController.loadPreset(...)` + `session.writeStateBlob(...)` flow already factored on the editor.

**Tests:** port `PresetStepperTests.swift` directly. It's a ViewModel-shaped test that asserts prev/next traversal and edge behaviour (empty preset list, single preset, wrap). Update any session-API mocking to use `session.writeStateBlob` typed mock.

- [ ] Port `PresetStepper` view from `a91cc15`
- [ ] Port `PresetStepperTests` and update for v2 typed-API mock
- [ ] Wire into `TrackDestinationEditor`'s preset section (the "CURRENT PRESET" card from `18d8b73`)
- [ ] Build + tests green
- [ ] Commit: `feat(au): inline preset stepper on destination card`

## Task 4 — Sampler destination card restyle

**Reference commit:** `9d808ee feat(sample): restyle sampler destination card` (+474/-195 across `SamplerDestinationWidget.swift`, `SamplerSettings.swift`, `SamplePlaybackEngine.swift`, plus unit-test updates).

Restyle of `SamplerDestinationWidget` to match the new AU card aesthetic. Side-effects in the diff are real: `SamplerSettings` got a small clamping/normalisation cleanup (gain remap), and `SamplePlaybackEngine` gained a thin test-surface (an init-time hook or a setter exposed for testability).

**Implementation:** start by reading `9d808ee` end-to-end — this is the largest of the polish commits. Re-author the visual layout against the post-18d8b73 widget on main. The `SamplerSettings`/`SamplePlaybackEngine` changes are document-model + audio-engine side and don't intersect with v2's session API; they should port near-verbatim. Update tests as needed.

**Tests:** `SamplerSettingsTests` and `SamplePlaybackEngineTests` already exist; max-8's diff added a small number of new assertions (+10 across both). Port those.

- [ ] Read `9d808ee` diff
- [ ] Port `SamplerSettings` clamping cleanup + tests
- [ ] Port `SamplePlaybackEngine` test surface + tests
- [ ] Restyle `SamplerDestinationWidget` to match the AU card; reuse the same shape primitives (rounded panel + eyebrow + body + action row) so the two destinations look like siblings
- [ ] Build + tests green
- [ ] Manual smoke: switch a track to a sample destination, verify gain slider, audition button, and waveform render
- [ ] Commit: `feat(sample): restyle sampler destination card`

## Task 5 — Layout polish

**Reference commits:** `45f9663`, `bf85314`, `5f507ea`. Three small fixes, one commit each.

- `45f9663 fix(au): fit destination card in side column` — destination card overflowed at narrower inspector widths. Fix is constraint-side: a `frame(maxWidth: .infinity)` or padding tweak.
- `bf85314 fix(ui): keep destination beside source` — at certain widths the destination panel dropped below the source panel. Layout fix to the parent container.
- `5f507ea fix(ui): keep track page interactive after sample restyle` — pointer events were eaten in the new sampler card layout. Regression fix from Task 4.

These are the kind of changes that need to be re-authored against the actual layout shape on main, not pasted from max-8. Read each diff for the bug being addressed; verify the bug still reproduces on current main; apply the equivalent fix.

If `5f507ea`'s root cause depended on a specific shape from `9d808ee` that you didn't faithfully reproduce in Task 4, the fix may not be needed at all — verify before adding.

- [ ] Verify each bug reproduces on current main (after Task 4 lands)
- [ ] Apply each fix; only commit fixes that address a real reproducer
- [ ] Build green
- [ ] Manual smoke: resize window across narrow / medium / wide inspector widths
- [ ] Commit(s): `fix(ui): destination card width`, `fix(ui): destination beside source`, optionally `fix(ui): track page hit-testing`

## Task 6 — Per-step macro lane slots in clips

**Reference commit:** `a01eeb5 feat(clip): add per-step macro lane slots` (13 files, +723/-58). The headline feature in this plan.

A per-step override lane on noteGrid clips, exposed in `ClipContentPreview` as a strip of "M1, M2, M3, …" slots. Tapping a slot binds it to one of the track's AU-parameter macros via `SingleMacroSlotPickerSheet`; once bound, the strip shows the macro's per-step overrides on the same step grid as triggers / velocity / probability.

This sits on top of Task 2's slot-index model — the slot picker writes `slotIndex` on the binding so the strip's M1/M2/M3 layout is stable.

### 6a — Document model

`TrackMacroBinding.slotIndex: Int` (Codable, with absent-key default). `ClipContent.noteGrid` payload gains `macroLanes: [UUID: MacroLane]` where the key is the binding id and the value is a `MacroLane` (per-step optional overrides over the binding's range). Project-side helpers: `addAUMacro(descriptor:to:slotIndex:)`, `removeMacro(id:from:)`, `syncMacroLayers()` reordering by slot.

Round-trip codable for everything; legacy decode without `slotIndex` falls back to insertion order.

- [ ] Tests: `TrackMacroDescriptorTests` slotIndex round-trip; `ProjectTrackMacroTests` slot ordering; `ClipContent` MacroLane round-trip
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): macro slot index + clip macro lanes`

### 6b — Snapshot compiler awareness

`SequencerSnapshotCompiler` resolves a clip macro lane override at step time, layered on top of the phrase-layer default. When a step has `macroLanes[bindingID][stepIndex] = some(value)`, that wins; otherwise the phrase layer's value applies.

- [ ] Test: a clip with a macro lane override fires through the snapshot at the expected step
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(engine): clip macro lane resolution`

### 6c — `SingleMacroSlotPickerSheet`

Modal sheet for choosing one AU parameter to bind to a slot. Lifts the parameter-tree fetch from `engineController.audioInstrumentHost(for: trackID)?.parameterReadout()`, applies the same name-match ranking as the existing `MacroPickerSheet` but selects one descriptor instead of a multi-select.

The commit handler uses the `session.batch` pattern (Task 1's architecture note) — `addAUMacro(descriptor:to:slotIndex:)` then `syncMacroLayers()` then publish. See `SequencerDocumentSession+Mutations.swift:applyMacroDiff` for the established pattern.

- [ ] Implement view
- [ ] Implement assignMacro typed-API call
- [ ] Manual smoke: tap an empty slot, pick a parameter, see the slot fill
- [ ] Commit: `feat(ui): SingleMacroSlotPickerSheet for per-slot macro binding`

### 6d — `ClipContentPreview` macro slot strip

Strip of M1..MN slot buttons sits above the existing trigger/velocity/probability mode picker. Tapping a slot:
- if bound: switches the editor's selected mode to that macro's lane
- if unbound: opens the slot picker sheet

When a macro slot is the selected mode, the cell grid edits `macroLanes[bindingID]` instead of velocity/probability.

The lane editor itself: reuse `ClipMacroLaneEditor` from main (the standalone editor that the AU card redesign introduced) — but invoke it inline inside `ClipContentPreview`, not as a separate panel below. Pass `showsHeader: false`.

- [ ] Add macro slot strip view
- [ ] Wire selected slot → `selectedMacroSlotIndex` → routes the cell grid through the lane editor
- [ ] `onUpdateMacroLanes` callback writes via `session.ensureClipAndMutate` setting `entry.macroLanes`
- [ ] Manual smoke: bind a macro slot, switch to it, set per-step values, watch them apply during playback
- [ ] Commit: `feat(ui): per-step macro lane in ClipContentPreview`

### 6e — `TrackSourceEditorView` wiring

Update `TrackSourceEditorView` to compute `clipMacroSlots` from `track.macros` ordered by `slotIndex`, pass `macroSlots`, `macroLanes`, `macroFallbackValues`, `onAssignMacroSlot`, and `onUpdateMacroLanes` into `ClipContentPreview`. Drop the now-redundant standalone `ClipMacroLaneEditor` block (the lane editor is inline in the preview now).

Use v2 typed APIs throughout — `session.ensureClipAndMutate` for content + lane updates; `session.batch` for the slot-assign flow.

- [ ] Wire props
- [ ] Drop the standalone `ClipMacroLaneEditor` block
- [ ] Build + manual smoke
- [ ] Commit: `feat(ui): wire ClipContentPreview macro slot strip from TrackSourceEditorView`

## Task 7 — Wiki + tag

- [ ] `wiki/pages/track-macros.md` (or update existing macros page) — document the slot model, the per-step lane, and the precedence rule (clip lane override > phrase layer default > descriptor default).
- [ ] `wiki/pages/track-destinations.md` — note the new `PresetStepper` and the macro slot row.
- [ ] Tag `v0.0.NN-au-card-and-macro-lanes` (increment NN against latest at completion).
- [ ] Mark this plan completed.

## Test plan (whole-plan)

- **Document:** macro slot index round-trip; macro lane round-trip; legacy decode without either; addAUMacro orders into the next free slot index.
- **Engine:** snapshot compiler honours clip macro lane override at step time; phrase layer default is the fallback.
- **UI ViewModels:** `PresetStepperTests` (next/prev/empty/single/wrap); slot picker pure ranker tests if the existing AU picker shares logic.
- **Manual smoke before tag:**
  1. Add an AU destination, pick three macros via the existing picker — verify they appear in slots M1/M2/M3 in order.
  2. Open the preset stepper inline; cycle through factory + user presets without opening the modal browser. No layout hangs.
  3. On a clip, tap M1's slot — selects the macro lane mode; tap a step to set an override; play through and verify the override applies (e.g. cutoff jumps on that step).
  4. Tap M3 (unbound) → picker sheet opens → choose a parameter → slot fills, ready to author its lane.
  5. Add a drum group to the project; verify existing macro layers survive (no orphaned bindings).
  6. Resize the inspector column down to its minimum width; verify the destination card and the source/destination panels stay laid-out cleanly.
  7. Switch a track to a sampler destination; verify the restyled card is interactive (gain slider, audition button respond).

## Reference: cherry-mark verification

Before starting, run:

```sh
git log --left-right --cherry-mark --oneline main...codex/max-8-destination-au | grep '^>'
```

This must show exactly the nine commits listed in "Scope: in" plus `93f931e` (the duplicate AU redesign that's already on main as `18d8b73`). If the list has drifted (e.g. one of the commits has equivalent already on main by patch-id and shows as `=`), drop that line item from the plan rather than re-implementing it.

## Goal-to-task traceability

| Reference commit | Task |
|---|---|
| `e2030f8 fix(au-presets): avoid preset browser layout deadlock` | 1 |
| `24eda8b fix(document): keep macro layers when adding drum groups` | 1 |
| `c06fb20 feat(au): simplify destination macro controls` | 2 |
| `a91cc15 feat(au): step presets inline` | 3 |
| `9d808ee feat(sample): restyle sampler destination card` | 4 |
| `45f9663 fix(au): fit destination card in side column` | 5 |
| `bf85314 fix(ui): keep destination beside source` | 5 |
| `5f507ea fix(ui): keep track page interactive after sample restyle` | 5 |
| `a01eeb5 feat(clip): add per-step macro lane slots` | 6 (subtasks a–e) |
| Documentation | 7 |

## Assumptions

- `codex/max-8-destination-au` exists locally and is preserved until this plan tags out. Lose it before then and the implementer has no design reference.
- Each task's commit history on main is independent (Task 1 → Task 7 is a recommended order, not a hard sequence). Tasks 2 and 6 are coupled — slot index has to land before per-step macro lanes can index into it. Task 5 depends on Task 4. Everything else is parallelisable.
- The `session.batch` pattern in `SequencerDocumentSession+Mutations.swift:applyMacroDiff` is the canonical example of a composite mutation under v2; if a port produces a different shape, it should be checked against that example.
