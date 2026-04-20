# PhraseWorkspace / Cell Preview Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the 1900-LOC `Sources/UI/PhraseWorkspaceView.swift` and the 357-LOC `Sources/UI/PhraseCellPreview.swift` along clean responsibility boundaries. Two separate workspace views are currently cohabiting one file; cell preview, editors, curve visualisation, and pure value-layer helpers are all mixed into one file. This split is explicitly fresh-model-only: it assumes the no-legacy destination/group cleanup has already landed, and it must not preserve or reintroduce compatibility bridges while moving code around. Verified by: both workspace views compile and render identically to pre-split; existing test suite green; the new `PatternIndexCellPreview` renders an 8-slot indicator instead of the current scalar-at-100%-fill hack; no SwiftUI file exceeds 600 LOC after the split.

**Architecture:** Pure structural decomposition. No behaviour changes except fixing the pattern-index render. Each split is driven by a single responsibility rule:

1. **View-per-file for workspace-level views.** `PhraseWorkspaceView` (matrix editor) and `LiveWorkspaceView` (live performance) must not share a file — they serve different user modes and evolve on different cadences.
2. **View-per-layer-type for cell previews.** Each `PhraseLayerValueType` case gets its own preview view so the shape of the visual can diverge (pattern-index grid ≠ scalar fill ≠ boolean pill). The existing shell `PhraseCellPreview` becomes a `@ViewBuilder switch`.
3. **Editors separate from previews.** Editors mutate, previews render. `ScalarValueEditor`, `PatternIndexPicker`, `PhraseCurvePreview`, `PhraseCurvePreset` move to a sibling directory.
4. **Pure value-layer helpers belong in `Document/`.** `valueLabel`, `scalarValue`, `scalarRatio`, `cellSummary`, `cycledValue`, `toggledBooleanValue` are model semantics; they don't import SwiftUI and don't belong in UI.
5. **`Style` enum is a coupling, not an abstraction.** It only exists to name two call sites; once the call sites live in different files, it collapses to a plain `CellPreviewMetrics` struct each caller constructs.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`. Follow-up to `docs/plans/2026-04-19-tracks-matrix.md` (which landed `PhraseCellPreview` consolidation in commits `9ca0abc`/`1bc2593`).

**Depends on:** `cleanup-post-reshape` plan MUST land first. This plan assumes the clean, post-bridge model — no `track.output`, no `track.audioInstrument`, no `TrackOutputDestination`, no `GeneratorKind.drumKit`/`.templateGenerator`. The split is executed against that cleaned model, not the hybrid one. Running the split before the cleanup would either cement the bridges into the new file layout or require a second round of edits per new file.

Can run before or after `characterization`. Running BEFORE characterization means the goldens pin the post-split module structure, which is probably what we want — otherwise the characterization plan pins the current 1900-LOC file and the split becomes a golden-breaking refactor.

**Deliberately deferred:**

- **Further UI decomposition beyond workspace-level.** `DetailView.swift`, `TrackSourceEditorView.swift`, `InspectorView.swift`, `TrackDestinationEditor.swift` are also large; scope-creeping into them turns a ~2-hour refactor into a rewrite. (A separate `track-source-split` plan is the natural follow-up.)
- **SwiftUI snapshot tests for the new views.** Covered by `qa-infrastructure` plan.

**Status:** `<STATUS_PREFIX>` `<COMPLETED_MARKER>` TBD. Tag TBD.

---

## File Structure

```
Sources/
  Document/
    PhraseLayer+Values.swift               # NEW — pure value-layer helpers moved out of UI
  UI/
    PhraseWorkspaceView.swift              # reduced: matrix editor only (~1000 LOC)
    LiveWorkspaceView.swift                # NEW — LiveWorkspaceView + LiveScopeCard + liveX helpers (~700 LOC)
    PhraseCellPreview.swift                # reduced: shell @ViewBuilder switch + CellPreviewMetrics (~80 LOC)
    PhraseCells/                           # NEW
      BooleanCellPreview.swift             # ~80 LOC
      ScalarCellPreview.swift              # ~60 LOC
      PatternIndexCellPreview.swift        # NEW — 8-slot indicator; was scalar-at-100% hack
    PhraseCellEditors/                     # NEW
      ScalarValueEditor.swift              # moved from PhraseCellPreview.swift
      PatternIndexPicker.swift             # moved
      PhraseCurvePreview.swift             # moved
      PhraseCurvePreset.swift              # moved
Tests/
  SequencerAITests/
    PhraseCellPreviewTests.swift           # extended: PatternIndexCellPreview renders 8 slots
    LiveWorkspaceViewTests.swift           # NEW if absent — minimal smoke
```

---

## Task 1: Extract pure value-layer helpers to `Document/`

**Scope:** Move the free functions out of UI into `Sources/Document/PhraseLayer+Values.swift` as extensions on `PhraseLayerDefinition` / `PhraseCellValue`. Responsibility: these encode model semantics (how a `PhraseCellValue` is interpreted against a `PhraseLayerDefinition`); they don't import SwiftUI and no UI-only type leaks into them.

**Files:**
- Create: `Sources/Document/PhraseLayer+Values.swift`
- Modify: `Sources/UI/PhraseCellPreview.swift` — delete the moved functions, update call sites

**Functions to move** (from `PhraseCellPreview.swift` lines 151-356):

- `cycledValue(_ value: PhraseCellValue, for layer:) -> PhraseCellValue`
- `toggledBooleanValue(_ value: PhraseCellValue, for layer:) -> PhraseCellValue`
- `valueLabel(_ value: PhraseCellValue, layer:) -> String`
- `scalarValue(for value: PhraseCellValue, layer:) -> Double`
- `scalarRatio(_ value: Double, layer:) -> Double`
- `cellSummary(_ cell: PhraseCell, layer:, phrase: PhraseModel) -> String`

Prefer method form where it reads well (`value.cycled(for:)`, `value.label(for:)`, `cell.summary(layer:phrase:)`) but a flat file of free functions is acceptable if a method form adds noise.

**Tests:**
- Existing tests that reference the free functions still pass unchanged.
- Add one test per moved function at unit-test granularity if coverage is thin (check existing `PhraseModelTests.swift` first — extend rather than duplicate).

- [ ] Move the six functions
- [ ] Update import and call sites across `UI/`
- [ ] Green
- [ ] Commit: `refactor(document): move phrase value-layer helpers out of UI`

---

## Task 2: Extract `LiveWorkspaceView` to its own file

**Scope:** Move `LiveWorkspaceView` (line 408), `LiveLaneScope` (line 986), `LiveScopeCard` (line 1012), and the seven `liveX` helper methods out of `PhraseWorkspaceView.swift` into `Sources/UI/LiveWorkspaceView.swift`. No behaviour change. Any `private` helpers that are now shared across files promote to `fileprivate` within their new owner, or `internal` if truly shared (prefer the former).

**Files:**
- Create: `Sources/UI/LiveWorkspaceView.swift`
- Modify: `Sources/UI/PhraseWorkspaceView.swift` — remove the moved types; adjust `DetailView.swift:238` call site if anything breaks (it shouldn't — `LiveWorkspaceView` stays same type).

**Symbols moved:**
- `struct LiveWorkspaceView`
- `struct LiveLaneScope`
- `struct LiveScopeCard`
- `liveEditor`, `liveSingleValueEditor`, `liveBarsEditor`, `liveStepsEditor`, `liveCurveEditor`, `liveValueEditor`, `liveValueLabel`

**Tests:**
- Existing test suite green with no test changes.
- If a `LiveWorkspaceViewTests.swift` doesn't exist, add a one-test smoke that instantiates the view (no assertion body — SwiftUI compile-time + render-time checks cover it).

- [ ] Extract the types
- [ ] Verify `DetailView.swift` still compiles
- [ ] Green
- [ ] Commit: `refactor(ui): extract LiveWorkspaceView to its own file`

---

## Task 3: Collapse `Style` enum into `CellPreviewMetrics`

**Scope:** With the two call sites now in separate files, `Style` (matrix vs live) is a name-only coupling. Replace with a plain `struct CellPreviewMetrics` carrying `booleanHeight`, `valueHeight`, `booleanAccentOpacity`, `muteOnOpacity` — each caller constructs its own instance. Delete the `Style` enum. The metric values themselves don't change; only the plumbing does.

**Files:**
- Modify: `Sources/UI/PhraseCellPreview.swift` — replace `Style` with `CellPreviewMetrics`
- Modify: `Sources/UI/PhraseWorkspaceView.swift` (matrix call site, line 1177) — pass `CellPreviewMetrics.matrix`
- Modify: `Sources/UI/LiveWorkspaceView.swift` (live call site, was line 1051) — pass `CellPreviewMetrics.live`

Two static factories on `CellPreviewMetrics` (`.matrix`, `.live`) keep call sites tidy. This is a struct with static factories, not an enum — callers can construct ad-hoc metrics for future views without extending an enum.

**Tests:**
- `PhraseCellPreviewTests.swift` continues to pass; update any test that instantiated `.style(.matrix)` or `.style(.live)`.

- [ ] Replace `Style` with `CellPreviewMetrics`
- [ ] Update both call sites
- [ ] Green
- [ ] Commit: `refactor(ui): replace PhraseCellPreview.Style with CellPreviewMetrics`

---

## Task 4: Split `PhraseCellPreview` into per-value-type views

**Scope:** The `PhraseCellPreview` struct's `body` switches on `layer.valueType` to route to boolean/scalar/patternIndex rendering. Extract each arm into its own struct in `Sources/UI/PhraseCells/`. The `PhraseCellPreview` shell becomes a 20-line `@ViewBuilder switch` dispatching to them.

**Files:**
- Modify: `Sources/UI/PhraseCellPreview.swift` — reduce to shell view + `CellPreviewMetrics`
- Create: `Sources/UI/PhraseCells/BooleanCellPreview.swift` — owns `booleanState`, `booleanLabel`, `booleanFill`, layout (mute-special-case stays here)
- Create: `Sources/UI/PhraseCells/ScalarCellPreview.swift` — owns the fill-ratio geometry + summary layout
- Create: `Sources/UI/PhraseCells/PatternIndexCellPreview.swift` — new visual: horizontal row of 8 mini-slot pills, current index highlighted; takes `fillRatio: 1.0` hack with it.

**Tests:**
- Extend `PhraseCellPreviewTests.swift`:
  - `test_boolean_preview_renders_mute_special_case` (existing coverage; re-point at `BooleanCellPreview`)
  - `test_scalar_preview_clamps_fillRatio`
  - `test_pattern_index_preview_highlights_current_slot` — **new test** asserting the new widget shape (current index pill is accented, others are inactive). This is a render-shape change, not a semantics change, so this test documents the fix for the scalar-at-100% hack.
- Run full test suite to confirm call-site changes are transparent to existing tests.

- [ ] Create the three per-type views
- [ ] Reduce `PhraseCellPreview` to the shell
- [ ] New `PatternIndexCellPreview` renders a slot grid, not a filled rectangle
- [ ] Tests green
- [ ] Commit: `refactor(ui): split PhraseCellPreview into per-value-type views`

---

## Task 5: Extract editors + curve widgets to `PhraseCellEditors/`

**Scope:** Move the four non-preview widgets currently squatting in `PhraseCellPreview.swift` into a sibling directory. These are editors and a curve visualiser — different responsibility from cell preview.

**Files:**
- Create: `Sources/UI/PhraseCellEditors/ScalarValueEditor.swift` (moved from `PhraseCellPreview.swift:186-218`)
- Create: `Sources/UI/PhraseCellEditors/PatternIndexPicker.swift` (moved from `:220-241`)
- Create: `Sources/UI/PhraseCellEditors/PhraseCurvePreview.swift` (moved from `:243-272`)
- Create: `Sources/UI/PhraseCellEditors/PhraseCurvePreset.swift` (moved from `:274-309`)
- Modify: `Sources/UI/PhraseCellPreview.swift` — delete the moved sections; final file ≤ 120 LOC.

**Tests:**
- No new tests required; existing editor tests continue to pass.

- [ ] Move the four widgets
- [ ] Verify `PhraseCellPreview.swift` is down to the shell + metrics only
- [ ] Green
- [ ] Commit: `refactor(ui): extract cell editors to PhraseCellEditors/`

---

## Task 6: Verify + close

**Scope:** Confirm the split left the app behaviourally identical and matches the architectural rules.

**Checks:**
- Full `xcodebuild test` passes.
- `find Sources/UI -name '*.swift' | xargs wc -l` shows no file over 1000 LOC (today `PhraseWorkspaceView.swift` is 1909 — target after Task 2 is ~1000; `DetailView` at 787 and `TrackSourceEditorView` at ~1100 are out of scope for this plan).
- `grep -rn 'import SwiftUI' Sources/Document/` returns zero lines (Document must not import SwiftUI; proves Task 1 cleanly moved only non-UI helpers).
- Manual smoke: launch the app, open a project, exercise phrase matrix editing + live workspace — both render identically, pattern-index cells now show a slot indicator instead of a solid fill.

- [ ] All three checks pass
- [ ] Manual smoke
- [ ] Commit: `chore: verify phrase workspace split`

---

## Task 7: Tag + mark completed

- [ ] Replace `- [ ]` with `- [x]` for completed steps
- [ ] Add `Status:` line
- [ ] Commit: `docs(plan): mark phrase-workspace-split completed`
- [ ] Tag (allocate next available patch version): `git tag -a vX.Y.Z-phrase-workspace-split -m "Split PhraseWorkspaceView + PhraseCellPreview along responsibility boundaries; new PatternIndexCellPreview replaces scalar-at-100% hack"`

---

## Goal-to-task traceability (self-review)

| Architectural rule | Task |
|---|---|
| Workspace views get their own files | Task 2 |
| Per-layer-type preview views | Task 4 |
| Editors separate from previews | Task 5 |
| Value-layer helpers move to Document | Task 1 |
| Style enum → per-call-site metrics | Task 3 |
| Pattern-index renders as slot grid, not scalar-at-100% | Task 4 |
| No regressions | Task 6 |

## Open questions resolved

- **`@ViewBuilder switch` vs protocol-based factory:** use `@ViewBuilder switch` in the shell view. A protocol + `AnyView` factory loses SwiftUI's structural diffing and gains no extensibility over the switch. New layer types add a switch arm and a file.
- **`Style` fate:** deleted. The fork only existed to name two call sites; when they live in different files, each constructs its own metrics struct.
- **Boolean mute special-case location:** stays in `BooleanCellPreview` (it's a layer-id-keyed visual variant and only applies to boolean). If a second layer ever needs a special-case render, consider a `PhraseLayerVisualStyle` value on `PhraseLayerDefinition` itself — but until then, the `layer.id == "mute"` check is localised to one file.
- **PatternIndex visual:** 8 horizontal mini-pills (labels "P1"…"P8"), current index accented, others dimmed. Matches the existing `PatternIndexPicker` aesthetic without being interactive — they're a preview, not an editor. Exact sizing to match `booleanHeight` so cells remain uniform.
- **Why not also split `DetailView` and `TrackSourceEditorView`:** out of scope. This plan's charter is the two files directly discussed in the associated review; expanding it turns a mechanical split into an unbounded UI rewrite. Follow-up plans can take them.
- **Relationship to `cleanup-post-reshape`:** **sequential, not orthogonal.** Cleanup lands first and produces the clean model this plan targets. This plan's file moves, extractions, and renames are executed against the post-cleanup codebase; any UI bindings touched during the split go directly to `track.destination` / `Destination` (never through retired accessors). Both should land before `characterization` so the goldens pin the intended shape.
- **No-legacy stance:** this plan is executed with a deletion-favouring posture (per `adversarial-2026-04-20-overly-accepting.md`). If during the split any cell preview, editor, or helper reads a legacy shape that the cleanup plan was supposed to have deleted, treat that as a cleanup-plan regression to fix in-place, not a compatibility case to preserve.
