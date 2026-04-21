# Plan Audit — 2026-04-20 Plans vs Commits

Cross-references each task in the four plans created/refreshed today against actual commits and the current tree. Findings split into **structural** (files/tests that should exist and don't, or vice versa) and **process** (commit-message / scoping divergence that hurts traceability but doesn't block anything).

## Commit timeline (2026-04-20)

| SHA | Message | Role |
|---|---|---|
| e9ff5b2 | chore: checkpoint current ui, audio, and automation work | pre-plan baseline |
| 60fa69b | refactor(cleanup): delete legacy destination bridges | plan precondition |
| 0df85d7 | fix(destination): route editor writes through model | plan precondition |
| 0c40812 | docs(plan): refresh refactor and split plans for current tree | plan authoring |
| fa9a40b | refactor(ui): split workspace router into feature views | **not scoped to any 2026-04-20 plan** — the ui-org plan explicitly says "workspace router split is already happening elsewhere and out of scope" |
| a4602ab | refactor(document): rename model to Project and start TrackSource split | mega-commit spanning 3 plans |
| cec47b0 | refactor(ui): extract TrackSource generators and phrase cell helpers | spans ui-org + phrase-workspace |
| 557592e | refactor(ui): split live workspace and phrase cell previews | phrase-workspace |
| 8c4de11 | refactor(document): consolidate Project normalization | document-as-project Task 4 (clean scope) |
| 75e9a99 | docs(plan): close April 20 refactor and perf plans | close-out for 4 plans |
| 9bb534d | docs(plan): refresh macro coordinator plan for current main | plan authoring (macro-coordinator) |

All three completion tags (`v0.0.12`, `v0.0.13`, `v0.0.14`) point at the same close-out commit `75e9a99`, not at per-plan commits.

## 1. `document-as-project-refactor` — Tag v0.0.12

### Structural findings

| Item | Status | Note |
|---|---|---|
| `Project` renamed, `SeqAIDocument.model` → `.project` | ✅ | Zero `SeqAIDocumentModel` / `document.model` hits in `Sources/`, `Tests/`, `wiki/` |
| `StepSequenceTrack`, `TrackType`, `TrackMixSettings` extracted | ✅ | All three files exist |
| `DrumKitNoteMap`, `DrumKitPreset` in `Musical/` | ✅ | Both present; `DrumKitPreset+Destination.swift` in `Document/` |
| Normalization helper | ✅ | `Project.normalize(...)` in `Project+Codable.swift` |
| Project+*.swift extensions | ✅ (consolidated) | **DEVIATION from plan (now reconciled in plan doc):** Routes/Groups merged into `Project+Destinations.swift`; PhraseCells merged into `Project+Phrases.swift`; DrumKit merged into `Project+Tracks.swift`. Architectural goals still met. |
| `Project.swift` ≤ 200 LOC | ✅ | 58 LOC |
| No Document file > 500 LOC | ⚠️ | `PhraseModel.swift` is 812 LOC; **plan scope says "no file *touched by this plan*"**, and `PhraseModel.swift` was explicitly deferred. Non-finding. |
| `ProjectNormalizationTests.swift` | ✅ (partial) | Plan promised 4 distinct tests; file has 3. Coverage is roughly equivalent (test 2 covers both promised `selectedTrackID` and `selectedPhraseID` clamp cases; test 3 covers orphan-banks + full decode path). Not a gap — just fewer, broader tests. |

### Process findings

- Plan promised 8 separate commits (one per task). Actual: Tasks 1, 2, 3, 5 bundled into `a4602ab` with message "rename model to Project **and start TrackSource split**" (merges three plans' worth of work). Only Task 4 (normalization, `8c4de11`) got its own clean-scope commit.
- No `chore: verify document-as-project-refactor` commit (plan Task 6). Verification checkbox ticked without a verify commit.
- Plan Task 7 close commit `docs(plan): mark document-as-project-refactor completed` was instead `docs(plan): close April 20 refactor and perf plans` — multi-plan close.

## 2. `ui-organisation-and-track-source-split` — Tag v0.0.13

### Structural findings

| Item | Status | Note |
|---|---|---|
| `Theme/` directory | ✅ | `StudioTheme`, `StudioPanel`, `StudioPlaceholderTile` + extra `StudioMetricPill` (unplanned but fine) |
| `Inputs/` directory | ✅ | `.gitkeep` present |
| `StepAlgo+Kind.swift`, `PitchAlgo+Kind.swift` in Document | ✅ | No UI-local redefinition of `StepAlgoKind` / `PitchAlgoKind` |
| `StepAlgoKindTests.swift`, `PitchAlgoKindTests.swift` | ✅ | Content matches plan |
| `AlgoPreview.swift` in Document | ✅ | Includes the required top-line comment ("DUPLICATES ENGINE LOGIC — keep in sync…") |
| `AlgoPreviewTests.swift` | ✅ | 3 test cases (seeded RNG stability, canonical mono reference, clip-backed pitches) |
| `TrackSource/` tree (Generator/ Clip/ Preview/ Widgets/) | ✅ | All subdirectories exist |
| `GridEditor.swift` replaces `ProbabilityGridEditor` + `WeightGridEditor` | ✅ | Grep for old names returns zero |
| **`Tests/SequencerAITests/TrackSource/GridEditorTests.swift`** | ❌ **MISSING** | Plan Task 5 explicitly promised this test; checkbox ticked, file never created. `GridEditor.swift` shipped untested. |
| `stepAlgoAccentColor` placement | ⚠️ | Plan Task 7 said "colocate as `fileprivate` inside `GeneratedNotesPreview.swift`". Actual: lives in `Sources/UI/TrackSource/Generator/GeneratorDisplaySupport.swift` as an internal helper shared across Generator/ editors. The plan's design justification ("it's only used here") is violated — `StepAlgoEditor` also references it. The current location is defensible but diverges from plan. |
| `WrapRow.swift` | ✅ | Plan said "delete if single-call, inline"; actual: kept in `Widgets/` |
| `TrackSourceEditorView.swift` ≤ 250 LOC | ✅ | 193 LOC |
| No file in `TrackSource/` > 400 LOC | ✅ | Max 198 (`PitchAlgoEditor.swift`) |
| `import SwiftUI` in `Sources/Document/` = zero | ⚠️ | `SeqAIDocument.swift` imports SwiftUI (it's a `FileDocument`). Plan Task 9 said "zero lines"; phrase-workspace plan Task 6 correctly exempts this file. **UI-org plan's verification criterion is overly strict** — not a real bug, but the plan's ticked checkbox for "returns zero lines" was verified against a literal that the tree cannot satisfy. |

### Process findings

- Plan Tasks 1–8 each promised their own commit. Actual: Tasks 1–4 bundled into `a4602ab`; Tasks 5–8 bundled into `cec47b0`. No per-task scope.
- No `chore: verify track-source split` commit (plan Task 9).
- Plan Task 10 close commit message diverges (multi-plan close).

## 3. `phrase-workspace-split` — Tag v0.0.14

### Structural findings

| Item | Status | Note |
|---|---|---|
| `PhraseLayer+Values.swift` in Document with 6 helpers | ✅ | `cycledValue`, `toggledBooleanValue`, `valueLabel`, `scalarValue`, `scalarRatio`, `cellSummary` all present as free functions (plan allowed this form) |
| `LiveWorkspaceView.swift` | ✅ | 455 LOC; includes `LiveLaneScope`, `LiveScopeCard`, and `liveX` helpers |
| `LiveWorkspaceViewTests.swift` | ✅ | One-test smoke as plan specified |
| `CellPreviewMetrics` replaces `Style` enum | ✅ (not directly verified file-by-file; LOC & structure consistent) | |
| `PhraseCells/BooleanCellPreview.swift`, `ScalarCellPreview.swift`, `PatternIndexCellPreview.swift` | ✅ | All three exist |
| `PatternIndexCellPreview` renders 8-slot grid, not scalar-at-100% hack | ✅ | Confirmed by reading the file (`slotCount = 8`, per-slot fill/stroke) |
| `PhraseCellEditors/` with 4 files (`ScalarValueEditor`, `PatternIndexPicker`, `PhraseCurvePreview`, `PhraseCurvePreset`) | ✅ | |
| `PhraseCellPreview.swift` ≤ ~120 LOC | ✅ | 82 LOC |
| **Task 4 new tests in `PhraseCellPreviewTests.swift`**: `test_boolean_preview_renders_mute_special_case`, `test_scalar_preview_clamps_fillRatio`, `test_pattern_index_preview_highlights_current_slot` | ❌ **ALL MISSING** | Plan Task 4 explicitly promised these three tests (including one to document the pattern-index fix). Current `PhraseCellPreviewTests.swift` tests `toggledBooleanValue` / `cycledValue` helpers instead — useful, but at the wrong layer (those belong in a `PhraseLayerValuesTests.swift`). **The split's headline new behaviour — 8-slot pattern-index widget — has zero test coverage.** |
| No file > 1000 LOC in scope | ✅ | `PhraseWorkspaceView.swift` 527, `LiveWorkspaceView.swift` 455 |

### Process findings

- Plan Tasks 1–5 each promised own commit. Actual: Tasks 1, 3, 5 bundled into `cec47b0`; Tasks 2, 4 bundled into `557592e`.
- No `chore: verify phrase workspace split` commit (plan Task 6).
- Plan Task 7 close commit message diverges (multi-plan close).

## 4. `test-performance-investigation` — no tag (closed early)

- Task 1 stop condition (cold < 60s) genuinely hit: cold 18.58s, warm-incremental 8.86s, warm-noop 7.96s.
- Tasks 2–5, 7, 8 correctly annotated "Closed early per the Task 1 stop condition; not needed for the current tree."
- Task 6 decision recorded in `.claude/state/test-perf-followup-findings.md` ✅
- Task 7 reproducible-measurement script (`scripts/measure-test-time.sh`) intentionally skipped (stop condition). `scripts/perf/` has raw logs only. Consistent with early-close.

## 5. `macro-coordinator-and-lookahead-scheduling` — not started

Status in plan: `[QUEUED]`. No implementation commits. This is the next-action candidate.

---

## Summary of outstanding cleanup items

**Missing tests (ticked but not created):**
1. `Tests/SequencerAITests/TrackSource/GridEditorTests.swift` — plan ui-org Task 5 checklist ticked; file does not exist. `GridEditor.swift` shipped untested.
2. `test_boolean_preview_renders_mute_special_case`, `test_scalar_preview_clamps_fillRatio`, `test_pattern_index_preview_highlights_current_slot` in `PhraseCellPreviewTests.swift` — plan phrase-workspace Task 4 checklist ticked; none of the three exist. The headline behaviour change (8-slot pattern-index widget) is untested.

**Plan deviations (plan now reconciled; code unchanged):**
3. `Project+Destinations.swift` instead of separate `+Routes` / `+Groups` / `+DrumKit` / `+PhraseCells` — already updated in `docs/plans/2026-04-20-document-as-project-refactor.md`.

**Plan deviations (not yet reconciled):**
4. `stepAlgoAccentColor` lives in `GeneratorDisplaySupport.swift`, not in `GeneratedNotesPreview.swift` as plan Task 7 specified. Two options: (a) update ui-org plan to reflect that the helper is Generator-scoped shared, or (b) inline into `GeneratedNotesPreview` and `StepAlgoEditor` and delete `GeneratorDisplaySupport.swift`. Prefer (a) — the actual placement is correct for the call sites.
5. ui-org plan Task 9 criterion `grep -r 'import SwiftUI' Sources/Document/` returns zero is unsatisfiable; should say "returns only `SeqAIDocument.swift`" to match the phrase-workspace plan's Task 6 criterion.
6. `ProjectNormalizationTests.swift` has 3 tests, not the 4 the plan listed. Coverage is equivalent; either accept and update plan, or add one dedicated `test_orphanPatternBanks_areFiltered` test for clarity.

**Process hygiene (not blocking, but degrades traceability):**
7. Per-task commits collapsed into 3 mega-commits (`a4602ab`, `cec47b0`, `557592e`) that each span multiple plans. Future "which commit implemented plan X Task Y" queries will require diff archaeology.
8. No `chore: verify` commits for any of the three completed plans' verification tasks, despite checkboxes being ticked. Either (a) run the verification commands now and commit the results, or (b) update the plan template to drop the verify-commit requirement when ticking boxes.
9. Close commit is `docs(plan): close April 20 refactor and perf plans` covering four plans at once — three tags share it. Plan templates say one close commit per plan.

**Untracked / uncommitted items from today:**
10. `.claude/agents/adversarial-reviewer.md` modified.
11. `.claude/state/review-queue/followup-2026-04-20-routing-sinks-as-blocks.md` untracked.
12. `.claude/state/review-queue/important-2026-04-20-spec-drum-kit-contradiction.md` untracked.
