# UI Organisation + Track-Source Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a feature-first directory structure for `Sources/UI/` (with a narrow shared-tier for theme + reusable inputs), and execute the first feature split against it: decompose the 1487-LOC `TrackSourceEditorView.swift` (25 top-level types, 7 responsibility clusters) into a coherent `TrackSource/` feature directory. Along the way: move the duplicated preview-engine logic into Document where it can be diff-reviewed against the real engine, and move algo-kind projections out of UI where they never belonged. This plan assumes the current fresh model only; it does not preserve legacy destination bridges, legacy document decoding, or retired UI compatibility shims. Verified by: `Sources/UI/TrackSource/TrackSourceEditorView.swift ≤ 250 LOC`; no UI file over 1000 LOC that the plan touched; `grep -r 'import SwiftUI' Sources/Document/` returns zero; `StepAlgoKind` / `PitchAlgoKind` live in Document as extensions, not as UI-private enums; full test suite green; app launches and the Source panel renders identically to pre-split.

**Architecture:**

Feature-first grouping for `Sources/UI/`, with two shared tiers:

- **`Theme/`** — visual tokens and panel chrome that already span every feature (`StudioTheme`, `StudioPanel`, `StudioPlaceholderTile`).
- **`Inputs/`** — genuinely shared input primitives. **Starts empty.** A widget is promoted here only when a *third* feature needs it; two consumers is not enough. No speculative promotion.
- **Feature directories** (e.g. `TrackSource/`) — own their sub-features, their feature-local widgets, and everything needed to understand the feature in one directory. Feature-local widgets live in `<Feature>/Widgets/` and stay there until the rule-of-three triggers promotion.

Existing shared files that are still flat (`InspectorView`, `TrackDestinationEditor`, `PhraseWorkspaceView`, `TrackSourceEditorView`, `PhraseCellEditorSheet`, `PhraseCellPreview`) are **not moved gratuitously.** The workspace-router split has already started: `WorkspaceDetailView.swift` routes into `Song/`, `Track/`, `Mixer/`, and `Library/`, and those directories are left alone by this plan. `LiveWorkspaceView` still lives inside `PhraseWorkspaceView.swift`, not as its own file. This plan only creates `Theme/`, `Inputs/` (empty), and `TrackSource/`.

Within `TrackSource/`, sub-features get their own directories (`Generator/`, `Clip/`, `Preview/`). A `Widgets/` directory holds feature-local widgets.

Two cross-cutting moves land in Document during the split:

- **Algo-kind projection** — `StepAlgoKind` and `PitchAlgoKind` currently live as UI-private `CaseIterable` enums, making the UI the authority on what counts as an algorithm variant. They move to Document as `extension StepAlgo { var kind: StepAlgoKind }` + enum, alongside the algos themselves.
- **Algo preview helpers** — `PreviewRNG`, `previewSteps`, `stepFiresPreview`, `pickPitchPreview` duplicate engine logic for display. Move to `Sources/Document/AlgoPreview.swift` so the duplication is at least diff-reviewable against the real algos. (A proper "call the real engine for preview" refactor is deferred.)

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`. Instance of the directory organisation discussed in the `phrase-workspace-split` conversation.

**Depends on:** the post-bridge cleanup and the destination-editor cleanup are already on `main` (`60fa69b`, `0df85d7`). TrackSource code reads `StepSequenceTrack`, `Destination`, algo types, and generator pool entries — executing this split before those landed would waste work migrating readers of APIs that are intentionally gone. This plan should also avoid touching the in-flight workspace-router files beyond any import-path fallout from creating `Theme/`.

Soft ordering:
- Prefer running AFTER `document-as-project-refactor` if that rename is in the queue, so TrackSource lands directly against `Project` / `document.project` rather than absorbing a second rename churn.
- Can run before or after `phrase-workspace-split`. Whichever lands first creates `Theme/`; the later plan uses it. This plan assumes `Theme/` does not yet exist; if `phrase-workspace-split` landed first, Task 1 becomes a no-op.
- Should run BEFORE `characterization` so the goldens pin the post-split structure.

**Deliberately deferred:**

- **Moving existing files into new feature directories beyond TrackSource.** `InspectorView`, `TrackDestinationEditor`, `PhraseWorkspaceView`, and the still-inline `LiveWorkspaceView` remain where they are. `WorkspaceDetailView.swift` plus the existing `Song/`, `Track/`, `Mixer/`, and `Library/` directories are already the result of a separate split and are explicitly not reworked here.
- **Further Track-Source decomposition beyond the cluster split.** If `PitchAlgoEditor` (214 LOC alone) deserves a per-pick-mode sub-split, that's a follow-up plan. This plan ships it as one file.
- **Calling the real engine for preview rather than duplicating its logic.** The preview helpers move to `Document/AlgoPreview.swift` *as they are*. Replacing them with a thin wrapper over the real engine is a separate refactor — it changes behaviour (might surface existing engine bugs in preview), so it deserves its own plan with its own goldens.
- **SwiftUI snapshot tests for TrackSource views.** Covered by `qa-infrastructure`.
- **UI `Chrome/` or `Layout/` directories.** Add if and when cross-feature chrome emerges; don't create speculatively.

**Status:** `<STATUS_PREFIX>` `<COMPLETED_MARKER>` TBD. Tag TBD.

---

## File Structure (post-plan)

```
Sources/
  Document/
    AlgoPreview.swift                               # NEW — PreviewRNG + previewSteps + stepFiresPreview + pickPitchPreview
    StepAlgo+Kind.swift                             # NEW — StepAlgoKind enum + computed projection on StepAlgo
    PitchAlgo+Kind.swift                            # NEW — PitchAlgoKind enum + computed projection on PitchAlgo
  UI/
    Theme/                                          # NEW shared tier
      StudioTheme.swift                             # MOVED
      StudioPanel.swift                             # MOVED
      StudioPlaceholderTile.swift                   # MOVED
    Inputs/                                         # NEW — starts empty
    TrackSource/                                    # NEW feature directory
      TrackSourceEditorView.swift                   # reduced shell (~200 LOC)
      TrackSourceModePalette.swift                  # moved
      TrackPatternSlotPalette.swift                 # moved
      Generator/
        GeneratorParamsEditorView.swift             # tab host
        GeneratorEditorTab.swift                    # enum
        GeneratorTabBar.swift                       # tab chrome
        StepAlgoEditor.swift
        PitchAlgoEditor.swift                       # consider per-pick-mode split in a follow-up
        NoteShapeEditor.swift
        PolyLaneSelector.swift
        SliceIndexEditor.swift
        GridEditor.swift                            # NEW — generic; replaces ProbabilityGridEditor + WeightGridEditor
      Clip/
        ClipContentPreview.swift
        ClipPianoRollPreview.swift
      Preview/
        GeneratedNotesPreview.swift
        AlgorithmSummaryCard.swift
      Widgets/                                      # feature-local widgets
        SourceParameterSliderRow.swift
        SourceParameterStepperRow.swift
        WrapRow.swift                               # delete if usage is single-call
    WorkspaceDetailView.swift                       # existing workspace router; left alone
    Song/
      SongWorkspaceView.swift                      # existing; left alone
    Track/
      TrackWorkspaceView.swift                     # existing; left alone
    Mixer/
      MixerWorkspaceView.swift                     # existing; left alone
    Library/
      LibraryWorkspaceView.swift                   # existing; left alone
    (existing flat/shared files unchanged:)
    InspectorView.swift
    TrackDestinationEditor.swift
    PhraseWorkspaceView.swift                      # still contains LiveWorkspaceView
    PhraseCellEditorSheet.swift
    PhraseCellPreview.swift
Tests/
  SequencerAITests/
    TrackSource/                                    # NEW test dir mirroring source
      GridEditorTests.swift                         # NEW — generic; covers former probability + weight specialisations
      (existing track-source tests stay and may relocate here for colocation)
  Document/
    AlgoPreviewTests.swift                          # NEW — covers the moved preview helpers
    StepAlgoKindTests.swift                         # NEW — minimal coverage of the kind projection
    PitchAlgoKindTests.swift                        # NEW
```

---

## Task 1: Establish shared `Theme/` directory

**Scope:** Create `Sources/UI/Theme/` and move `StudioTheme`, `StudioPanel`, `StudioPlaceholderTile` into their own files inside it. No behaviour change; pure mechanical move. Also create an empty `Sources/UI/Inputs/` with a `.gitkeep` or a one-line placeholder so the directory intent is visible in the tree.

**Files:**
- Create: `Sources/UI/Theme/StudioTheme.swift` (moved from wherever it currently lives)
- Create: `Sources/UI/Theme/StudioPanel.swift`
- Create: `Sources/UI/Theme/StudioPlaceholderTile.swift`
- Create: `Sources/UI/Inputs/.gitkeep` (or a marker comment file)
- Delete: the old locations of the three types

**Tests:** Existing test suite continues to pass. No new tests.

- [ ] Locate `StudioTheme` / `StudioPanel` / `StudioPlaceholderTile` current homes
- [ ] Move into `Theme/` (one type per file)
- [ ] Verify Xcode project file / `xcodegen` regeneration picks up the new locations
- [ ] `xcodebuild build` green
- [ ] Commit: `refactor(ui): establish Theme/ and Inputs/ shared-tier directories`

**Note:** If `phrase-workspace-split` has already landed and created `Theme/`, this task becomes a no-op — verify and skip to Task 2.

---

## Task 2: Move algo kind projections to Document

**Scope:** `StepAlgoKind` and `PitchAlgoKind` are UI-private `CaseIterable` enums that project `StepAlgo` / `PitchAlgo` cases into a discriminator for the Picker selector. Move both to Document as extensions on the algo types, so the UI stops being the authority on what a "kind" is.

**Files:**
- Create: `Sources/Document/StepAlgo+Kind.swift` — defines `StepAlgoKind` (moved) + `extension StepAlgo { var kind: StepAlgoKind }` + `extension StepAlgoKind { func defaultAlgo() -> StepAlgo }` (the current `defaultStepAlgo(for:)` helper migrates here).
- Create: `Sources/Document/PitchAlgo+Kind.swift` — same pattern for `PitchAlgoKind` + `defaultPitchAlgo(for:)`.
- Modify: `Sources/UI/TrackSourceEditorView.swift` — delete the local enums and helper functions. Call `StepAlgo.kind`, `PitchAlgo.kind`, `StepAlgoKind.defaultAlgo()`, `PitchAlgoKind.defaultAlgo()` instead.
- Delete from UI: `private enum StepAlgoKind` (line 426), `private enum PitchAlgoKind` (line 843), `private func defaultStepAlgo(for:)` (line 1185), `private func defaultPitchAlgo(for:)` (line 1206).

**Tests:**
- Create: `Tests/SequencerAITests/Document/StepAlgoKindTests.swift` — `StepAlgo` → `StepAlgoKind` projection is stable for every case; `StepAlgoKind.defaultAlgo()` round-trips back to the same kind.
- Create: `Tests/SequencerAITests/Document/PitchAlgoKindTests.swift` — same.
- Existing editor tests continue to pass.

- [ ] Move the two enums + two helpers to Document
- [ ] Update UI call sites
- [ ] Add the two new test files
- [ ] Green
- [ ] Commit: `refactor(document): move algo-kind projections out of UI`

---

## Task 3: Move preview-engine helpers to Document

**Scope:** `PreviewRNG`, `previewSteps`, `stepFiresPreview`, `pickPitchPreview`, `clipPitches`, `stepAlgoAccentColor` are currently UI-private. The first four duplicate engine logic; colocate them with the real algos so the duplication is at least visible at code-review time. `stepAlgoAccentColor` is UI theming — stays in UI (eventually moves to `Theme/` or a per-feature theme file).

**Files:**
- Create: `Sources/Document/AlgoPreview.swift` — moved bodies for `PreviewRNG`, `previewSteps`, `stepFiresPreview`, `pickPitchPreview`, `clipPitches`. File opens with a top-line comment: `// Preview-only dry run of step/pitch algos. DUPLICATES ENGINE LOGIC — keep in sync with Sources/Engine/Blocks/*. Tracked for consolidation in a follow-up plan.`
- Modify: `Sources/UI/TrackSourceEditorView.swift` — delete the moved helpers. Update call sites (all inside what will become `Preview/GeneratedNotesPreview.swift`).
- Modify: `Sources/UI/TrackSourceEditorView.swift` — leave `stepAlgoAccentColor(for:)` in place (UI concern); it will move to `TrackSource/` in Task 4's root-extract.

**Tests:**
- Create: `Tests/SequencerAITests/Document/AlgoPreviewTests.swift` — seeded `PreviewRNG` produces identical output across runs; `previewSteps` output matches a captured reference for one canonical `GeneratorParams.mono` configuration (this is effectively a mini characterization test for the preview path).

- [ ] Move the four preview helpers + RNG to Document
- [ ] Update UI call sites
- [ ] Add `AlgoPreviewTests`
- [ ] Green
- [ ] Commit: `refactor(document): colocate algo preview helpers with algos`

---

## Task 4: Extract TrackSource root components

**Scope:** Create `Sources/UI/TrackSource/`. Move `TrackSourceEditorView` (keep the main type in-place but relocate the file), plus `TrackSourceModePalette` and `TrackPatternSlotPalette`, into their own files. At this point `TrackSourceEditorView.swift` is the thin shell that still contains the 7 sub-feature clusters (to be extracted in subsequent tasks).

**Files:**
- Create: `Sources/UI/TrackSource/TrackSourceEditorView.swift` — moved from its current location. File retains all its current sub-types (will shrink in later tasks).
- Create: `Sources/UI/TrackSource/TrackSourceModePalette.swift` — moved from lines 1345-1389.
- Create: `Sources/UI/TrackSource/TrackPatternSlotPalette.swift` — moved from lines 1390-1455.
- Modify: `Sources/UI/TrackSource/TrackSourceEditorView.swift` — private types below the main struct remain; this task only relocates the file and extracts the two palette views.
- Move: `stepAlgoAccentColor(for:)` into `TrackSource/TrackSourceEditorView.swift` as `fileprivate` for now; promotion decision deferred until the preview extract in Task 7.

**Tests:** Existing suite green, no new tests.

- [ ] Create `TrackSource/` directory
- [ ] Move main file + two palettes
- [ ] Verify Xcode project / xcodegen regeneration
- [ ] Green
- [ ] Commit: `refactor(ui): extract TrackSource/ root and palettes`

---

## Task 5: Extract Generator/ sub-feature

**Scope:** Move the 10 generator-cluster types into `Sources/UI/TrackSource/Generator/`. Also collapse `ProbabilityGridEditor` + `WeightGridEditor` into a single generic `GridEditor` — the second is already a trivial 9-line wrapper, and keeping them separate invites more drift.

**Files:**
- Create: `Sources/UI/TrackSource/Generator/GeneratorParamsEditorView.swift`
- Create: `Sources/UI/TrackSource/Generator/GeneratorEditorTab.swift`
- Create: `Sources/UI/TrackSource/Generator/GeneratorTabBar.swift`
- Create: `Sources/UI/TrackSource/Generator/StepAlgoEditor.swift`
- Create: `Sources/UI/TrackSource/Generator/PitchAlgoEditor.swift`
- Create: `Sources/UI/TrackSource/Generator/NoteShapeEditor.swift`
- Create: `Sources/UI/TrackSource/Generator/PolyLaneSelector.swift`
- Create: `Sources/UI/TrackSource/Generator/SliceIndexEditor.swift`
- Create: `Sources/UI/TrackSource/Generator/GridEditor.swift` — generic replacement for `ProbabilityGridEditor` + `WeightGridEditor`. Signature roughly `GridEditor<Value>(title: String, values: Binding<[[Value]]>, range: ClosedRange<Value>) where Value: BinaryFloatingPoint`.
- Modify: `Sources/UI/TrackSource/TrackSourceEditorView.swift` — delete the 10 extracted types and the old grid editors.

**Tests:**
- Create: `Tests/SequencerAITests/TrackSource/GridEditorTests.swift` — covers the generic editor against both former specialisations (probability range `0...1`, weight range `0...N`).
- Existing editor tests continue to pass with any import adjustments.

- [ ] Extract the 8 generator views
- [ ] Replace probability + weight editors with generic `GridEditor`
- [ ] Add `GridEditorTests`
- [ ] Green
- [ ] Commit: `refactor(ui): extract Generator/ sub-feature + collapse grid editors`

---

## Task 6: Extract Clip/ sub-feature

**Scope:** Move `ClipContentPreview` and `ClipPianoRollPreview` into `Sources/UI/TrackSource/Clip/`. The `clipPitches(for clip:)` helper already moved to Document in Task 3.

**Files:**
- Create: `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`
- Create: `Sources/UI/TrackSource/Clip/ClipPianoRollPreview.swift`
- Modify: `Sources/UI/TrackSource/TrackSourceEditorView.swift` — delete the moved types.

**Tests:** Existing suite green.

- [ ] Extract the two clip views
- [ ] Green
- [ ] Commit: `refactor(ui): extract Clip/ sub-feature`

---

## Task 7: Extract Preview/ sub-feature

**Scope:** Move `GeneratedNotesPreview` and `AlgorithmSummaryCard` into `Sources/UI/TrackSource/Preview/`. Their preview-engine helpers already live in Document (Task 3). `stepAlgoAccentColor(for:)` is only used here — colocate it as `fileprivate` inside `GeneratedNotesPreview.swift`; if a second feature ever uses accent-by-algo-kind, promote.

**Files:**
- Create: `Sources/UI/TrackSource/Preview/GeneratedNotesPreview.swift`
- Create: `Sources/UI/TrackSource/Preview/AlgorithmSummaryCard.swift`
- Modify: `Sources/UI/TrackSource/TrackSourceEditorView.swift` — delete the moved types and `stepAlgoAccentColor`.

**Tests:** Existing suite green.

- [ ] Extract the two preview views
- [ ] Colocate `stepAlgoAccentColor` in `GeneratedNotesPreview.swift`
- [ ] Green
- [ ] Commit: `refactor(ui): extract Preview/ sub-feature`

---

## Task 8: Extract local Widgets/

**Scope:** Move `SourceParameterSliderRow`, `SourceParameterStepperRow`, and `WrapRow` into `Sources/UI/TrackSource/Widgets/`. These are feature-local until the rule-of-three triggers promotion to `Inputs/`. `WrapRow` specifically: check whether it has more than one caller; if single-use, inline at the caller and delete the file.

**Files:**
- Create: `Sources/UI/TrackSource/Widgets/SourceParameterSliderRow.swift`
- Create: `Sources/UI/TrackSource/Widgets/SourceParameterStepperRow.swift`
- Create: `Sources/UI/TrackSource/Widgets/WrapRow.swift` — **OR** delete `WrapRow` entirely if it has one caller (inline there).
- Modify: `Sources/UI/TrackSource/TrackSourceEditorView.swift` — delete the moved types.

After this task, `TrackSourceEditorView.swift` is the shell: the main struct + its bindings + 2-3 tiny helper methods. Target size ≤ 250 LOC.

**Tests:** Existing suite green.

- [ ] Decide `WrapRow` fate (grep for callers)
- [ ] Extract the remaining two widgets
- [ ] Verify final `TrackSourceEditorView.swift` size
- [ ] Green
- [ ] Commit: `refactor(ui): extract TrackSource/Widgets/`

---

## Task 9: Verify + close

**Scope:** Confirm structural goals and document discipline.

**Checks:**
- `xcodebuild test` — full suite green.
- `wc -l Sources/UI/TrackSource/TrackSourceEditorView.swift` — ≤ 250 LOC.
- `find Sources/UI/TrackSource -name '*.swift' -exec wc -l {} +` — no file over 400 LOC (except `PitchAlgoEditor.swift`, explicitly deferred for further sub-split).
- `grep -r 'import SwiftUI' Sources/Document/` — returns zero lines.
- `grep -rn 'StepAlgoKind\|PitchAlgoKind' Sources/UI/` — returns only references to the Document-owned types (no local redefinition).
- `grep -rn 'ProbabilityGridEditor\|WeightGridEditor' Sources/` — returns zero (both collapsed into generic `GridEditor`).
- Manual smoke: launch the app, open a project, cycle through Step/Pitch/Note-shape editors, switch between generator and clip modes, exercise the preview panel. No visual regression vs pre-split.

- [ ] All checks pass
- [ ] Manual smoke
- [ ] Commit: `chore: verify track-source split`

---

## Task 10: Tag + mark completed

- [ ] Replace `- [ ]` with `- [x]` for completed steps
- [ ] Add `Status:` line after Parent spec
- [ ] Commit: `docs(plan): mark ui-organisation-and-track-source-split completed`
- [ ] Tag (allocate next available): `git tag -a vX.Y.Z-ui-org-track-source -m "Feature-first UI directory structure established; TrackSource split from 1487-LOC monolith into 15 cluster-local files; algo-kind projections and preview helpers moved to Document"`

---

## Goal-to-task traceability

| Architectural goal | Task |
|---|---|
| `Theme/` shared tier established | 1 |
| `Inputs/` empty shared tier established | 1 |
| Algo-kind authority moves from UI to Document | 2 |
| Preview-engine duplication colocated with algos for review | 3 |
| TrackSource feature directory with Generator/Clip/Preview/Widgets | 4, 5, 6, 7, 8 |
| Grid editors consolidated via generic | 5 |
| No UI file over 1000 LOC in scope | 9 |
| No Document file imports SwiftUI | 9 |

## Open questions

- **`PitchAlgoEditor` further split:** 214 LOC — the biggest single file post-split. If the pick-mode editors inside (`.randomInScale`, `.markov`, `.sequence`, `.slice`) each deserve their own sub-view, that's a follow-up. Deferred to keep this plan bounded.
- **Inline vs extract `WrapRow`:** decide at Task 8 based on actual caller count. Default to delete.
- **Preview-engine consolidation:** the real fix is to call the engine for preview, not duplicate its dispatch. Deferred — changes behaviour, needs goldens, separate plan.
- **Generic `GridEditor` bounds:** `BinaryFloatingPoint` is likely the right constraint but the weight editor may use a wider numeric range. Confirm at Task 5 implementation; widen constraint or generalise with a protocol if needed.
- **Test directory mirroring:** `Tests/SequencerAITests/TrackSource/` is created fresh for the new `GridEditorTests`. Existing TrackSource tests can migrate into it opportunistically, but are not required to move as part of this plan (test colocation is not a goal here).
- **Extending the convention:** this plan establishes the directory pattern via one feature. `InspectorView`, `TrackDestinationEditor`, `PhraseWorkspaceView`, and the remaining inline `LiveWorkspaceView` can migrate when plans touch them. The existing `Song/`, `Track/`, `Mixer/`, and `Library/` directories stay as-is. A "convert everything" sweep is explicitly not recommended — gratuitous moves are churn without payoff.
