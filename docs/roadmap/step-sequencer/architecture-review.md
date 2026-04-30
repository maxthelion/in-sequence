---
verdict: accepted
reviewed: 2026-04-30
---

# Step Sequencer — Architecture Review

Reviewed against: `architecture.md` (written 2026-04-29), `ux-review.md` (accepted, Variant D
selected, 2026-04-30), `existing-state.md`, `user-stories.md`,
`wiki/pages/architecture-guardrails.md`, `wiki/pages/document-model.md`,
`wiki/pages/engine-architecture.md`.

---

## 1. Data / Runtime Shape — Does the Model Fit?

### 1a. Approved: Selection State as Transient View-Model Type

`StepSelectionModel` as a value type (or `@Observable` class) owned by a coordinator is the
correct shape. It mirrors the project-wide guardrail that authored musical state lives in
`.seqai` and transient UI/runtime state does not. `existing-state.md` confirms there is no
selection state in `ClipContent`, `ClipPoolEntry`, or `StepSequenceTrack` today, so the
architecture does not introduce any new document pollution.

The field shape (`clipID: ClipID`, `selectedStepIndexes: Set<Int>`) is minimal and correct.
The `Set<Int>` avoids indexing assumptions and supports multi-step selection directly.

One concern: the architecture says `StepSelectionModel` is "discarded when the user navigates
away from that clip." This is correct for the persistence guardrail but the spec must clarify
what "navigate away" means in practice — specifically whether switching the active layer, switching
the active track, or closing the track workspace each independently clears selection. The lifetime
rule should be explicit in the spec.

### 1b. Approved: `StepClipboard` as Session-Scoped Transient State

`StepClipboard` is explicitly not persisted. Its shape (`sourceClipID`, `steps: [Int:
StepClipboardEntry]`) is array-indexed (per the guardrail for sequencer data) and covers all
per-step data layers. This is appropriate.

The unresolved copy/paste scope question (all-layers vs active-layer-only) does not block the
type shape — the all-layers structure is a superset and is the right default. The spec should
resolve the question, but the architecture's structural choice is defensible.

### 1c. Approved: `ClipBuffer` / `PlaybackSnapshot` Are Not Touched

The architecture correctly does not propose changing `ClipBuffer`, `PlaybackSnapshot`,
`PhrasePlaybackBuffer`, or `SequencerSnapshotCompiler`. The step-sequencer feature is entirely
a UI and model-mutation concern; the engine hot path reads compiled buffers and does not need
to know about selection, batch edits, or clipboard state. This satisfies the playback-snapshot
guardrail.

### 1d. Noted Gap: Chord-Generator Step Data Shape

The architecture acknowledges that chord identity per step is not in `ClipContent.noteGrid` and
defers the `chordLabel` cell variant to a stub. This is the correct approach given the current
model state. The architecture's proposed `StepCellContent.chordLabel(name: String)` case allows
the cell to render whatever a caller provides, without coupling the cell primitive to the
chord-generator track type's internal model. This is clean.

However, the architecture does not address how the coordinator (which is responsible for
converting track-type-specific model data to `StepCellContent`) would obtain chord identity for
a chord-generator track even in the non-stub future. The `existing-state.md` notes that chord
data is stored as raw notes in `ClipContent.noteGrid`, not as a chord abstraction. The spec must
say either (a) chord identity is always stubbed for this feature's scope, or (b) the
chord-generator track type provides a mapping path the coordinator can call. This is an open
question for the spec, not an architecture blocker.

---

## 2. Transient vs Persisted State — Boundary Assessment

The architecture draws the transient/persisted boundary correctly on all counts:

| State | Architecture Decision | Assessment |
|---|---|---|
| Step on/off, velocity, chance | Persisted in `ClipContent`, written via `session.mutateClip` | Correct |
| Per-step macro overrides | Persisted in `ClipPoolEntry.macroLanes`, written via `session.mutateClip` | Correct |
| Step selection set | Transient: `StepSelectionModel` in coordinator | Correct |
| Clipboard | Transient: `StepClipboard` in coordinator | Correct |
| Drag intent (in-progress drag) | Implicit: view gesture state, never persisted | Not explicitly stated — see note below |
| Rotary row mode (selection mode active) | Derived from `selectedStepIndexes.isEmpty` | Correct |
| Active layer tab | Existing: `ClipEditorMode` owned by parent; coordinator reads but does not own | Correct |

The drag-intent omission is minor but the spec should make it explicit: in-progress drag state
is local to the gesture recognizer and is never materialized as a named object. The architecture
implies this but does not state it.

The phrase-level vs clip-level macro write path (Section 7, Open Question 2) is correctly called
out as an unresolved boundary. The architecture cannot close this without a product decision: the
`PhraseCell.steps([PhraseCellValue])` storage and the `ClipContent.MacroLane` storage are
genuinely different editing surfaces. See Section 5 below.

---

## 3. Guardrails — Respected vs Missed

### Respected

**Document truth vs runtime state (guardrail 1).** Selection, clipboard, and drag intent are all
kept out of the `.seqai` document. No new `Codable` additions are proposed. The architecture
is explicit on this point.

**Playback snapshots and buffers (guardrail 2).** The architecture proposes no changes to the
compiled buffer layer or the snapshot compiler. All per-step writes go through `session.mutateClip`
and will flow into the existing snapshot invalidation path. The 16 ms budget is preserved because
all batch writes are a single closure.

**Array-style sequencer data (guardrail 3).** `StepSelectionModel.selectedStepIndexes: Set<Int>`
and `StepClipboard.steps: [Int: StepClipboardEntry]` are both step-indexed. The
`StepClipboardEntry` fields are parallel arrays or optional scalars, consistent with the existing
`ClipContent` shape. No feature-specific storage that fights the array shape is introduced.

**Small boundaries over broad rewrites (guardrail 4).** The architecture explicitly preserves
all existing cell types (`StepGridCell`, `MacroLaneCell`, `SliceStepStrip`, `GridEditor`) in
place and introduces `UnifiedStepCell` as a new type alongside them. Incremental migration is
the stated plan. No wholesale replacement is required for the feature to ship. This is the right
scope boundary.

**Realtime / future audio thread rules (guardrail 4).** The architecture does not propose changes
to render-thread code. All new types live in the UI/coordinator layer. The actor-isolation note
in Section 6 of `architecture.md` (batch closures must not escape non-Sendable state) is a
correct constraint for the implementation loop.

### Missed or Under-Specified

**`StepGridCoordinator` lifecycle and ownership.** The architecture says it is "instantiated per
clip-editing context and discarded when the context closes" but does not identify the owner.
This is a correctness risk: if the coordinator is owned by a view's `@State`, selection state
will be lost on view recreation (e.g., navigation). If it is owned by the session or document,
it violates the transient-state guardrail. The coordinator must be owned by a stable, non-view
object (e.g., a view model injected via environment or passed as a reference type). The spec
must name the owner.

**`session.mutateClip` actor isolation — no escape hatch for UI state.** Section 6 of the
architecture notes that "batch closures must not escape non-Sendable state." This is correct but
the architecture does not address the consequence: any `StepSelectionModel` or `StepClipboard`
reference captured in a `mutateClip` closure must either be `Sendable` or the values must be
copied before the closure is formed. This is an implementation constraint but the spec should
acknowledge it so the implementer does not discover it mid-build.

**Batch action bar — hidden vs collapsed.** The architecture says the batch action bar is
"hidden to avoid layout shift." `existing-state.md` documents that no batch action bar exists
today. The spec must define whether the bar is hidden via `opacity(0)` / `allowsHitTesting(false)`,
`hidden()`, or zero-height with `clipped()`. This is a presentation detail but the architecture's
stated rationale (avoid layout shift) constrains the choice. It should be stated in the spec.

**`MacroLane` indexing by `TrackMacroBinding` index.** The architecture correctly notes in
Section 6 that macro override writes must index by `TrackMacroBinding` index, not by implicit
layer order. This is a real risk (existing-state shows layer order can differ between views), but
the architecture does not describe how the coordinator resolves the binding index from the active
layer tab selection. The spec must define this mapping.

---

## 4. Open Questions from UX Review — Architecture Coverage

The `ux-review.md` surfaced six open questions. This review assesses whether the architecture
answers, defers, or leaves them open.

### UX Question 1 — Absolute vs Relative Rotary Semantics

**Status: deferred (correctly).**

The architecture does not decide this. Section 4d describes the rotary row calling the same
batch write path as a value, without specifying whether the value is absolute or relative. This
is the right approach at architecture stage: the write path is the same either way; the product
decision determines the value computed before the write. The spec must resolve this.

### UX Question 2 — Active-Layer vs All-Layers Rotary Row

**Status: implicitly answered (all-layers is the selected direction), but not stated.**

The architecture (Section 4d) says "each layer entry gains an inline rotary or arc-scrubber
control" when steps are selected — consistent with the Variant D prototype showing all editable
layers simultaneously. The architecture does not explicitly state this as a decision. The spec
should confirm this and handle the overflow case (more than N layers).

### UX Question 3 — Trigger Layer and the Rotary Row

**Status: open in architecture, should be resolved in spec.**

The architecture does not address what the rotary row shows when the active layer is `trigger`.
The UX review asks whether the row shows a "toggle all" action or nothing. The architecture's
Section 4d only describes the non-trigger case. The spec must define this explicitly.

### UX Question 4 — Touch Gesture

**Status: deferred, explicitly or implicitly.**

The architecture (Section 4c) describes "right-click (macOS) or long-press (touch)" for
selection and notes the gesture must not conflict with drag. Variant D's touch path was
not prototyped. The architecture does not add new constraints here. The spec should either
include the touch path in scope or explicitly defer it.

### UX Question 5 — Chord Dot Legibility at Production Scale

**Status: open, not addressed in architecture.**

The architecture defers chord-generator cell representation entirely. Legibility at production
scale is a UX concern; the spec should state a fallback (chord name label only at narrow widths)
or confirm that the dot representation is the direction and will be validated during implementation.

### UX Question 6 — Rotary Row Overflow at High Layer Counts

**Status: noted as layout risk (Section 3d of UX review), partially addressed.**

The architecture (Section 4d) notes that the choice of rotary control type "affects how many
layers can fit in the row simultaneously" and flags this as a question for the spec. The
architecture does not define a maximum or an overflow strategy. The spec must set a threshold
(e.g., maximum four editable layers before overflow handling is required) and name the handling
approach (scroll, collapse, or "more layers" affordance).

---

## 5. Architecture Questions That Must Be Answered Before Spec

The following are questions the architecture correctly raised or inadvertently left open that
the spec writer cannot guess.

1. **Who owns `StepGridCoordinator`?** The owner must be a stable, non-view reference type
   (not `@State`) to prevent selection state loss on view recreation. Candidate owners: a
   dedicated view model injected via SwiftUI environment, or a coordinator owned by the track
   workspace view model. The architecture does not name one.

2. **Which storage layer does the rotary write to for macro layers?** Open Question 2 in
   `architecture.md` asks whether turning a macro-layer rotary writes to
   `ClipContent.MacroLane` overrides (per-step, per-clip) or to `PhraseCell.steps`
   phrase-level values. These are different storage paths. The UX context (rotary in the step
   grid layer row, operating on selected steps within a clip editor) strongly implies
   `ClipContent.MacroLane`, but the architecture defers the decision. **This is the highest-risk
   open question for spec.** If the answer is phrase-level, the write path through
   `session.mutateClip` on a `ClipPoolEntry` is wrong, and a different mutation API is needed.

3. **`StepSelectionModel` lifetime rule.** What events clear selection? At minimum: (a)
   navigating away from the clip-editing context, (b) document close. Optionally: (c)
   switching the active track, (d) switching the active layer, (e) entering playback-only
   mode. The spec must enumerate these.

4. **Copy/paste scope — all-layers or active-layer-only?** The architecture adopts all-layers
   as the default structure but leaves the product decision open. This affects `StepClipboardEntry`
   and the paste write path (single-layer filtered write vs full multi-layer write). Must be
   resolved before spec.

---

## 6. Rejected or Revised Guardrails

None of the guardrails proposed in `architecture.md` are rejected. The architecture does not
introduce broad rewrites, duplicated playback paths, or document-as-UI-cache antipatterns.

One guardrail is **revised in scope**: the architecture's "incremental migration" framing for
`UnifiedStepCell` is correct but the spec should be explicit that existing views (`StepGridView`,
`ClipMacroLaneEditor`, `SliceTrackWorkspaceView`) are not required to migrate to
`UnifiedStepCell` within this feature's scope. Only the views that are directly modified to
implement the user stories need to use the new primitive. Forcing a full migration of all call
sites within this feature would turn a focused improvement into a broad rewrite.

---

## 7. Recommendation

The architecture is coherent, well-grounded in the existing codebase, and does not violate any
project guardrails. The model boundary decisions (transient selection, transient clipboard,
single-closure batch writes) are correct.

The five open questions in Section 5 above are not blockers for starting the spec — the
architecture provides enough structure to write the happy path. However, two of them
(coordinator ownership and macro-layer write path) carry implementation risk large enough that
the spec writer must explicitly call them out and either resolve them or mark them as
implementation-loop decisions with explicit fallback constraints.

**Verdict: accepted.** Advance to `write-spec`.

The spec should:
- Resolve or explicitly defer the six questions above.
- Name the owner of `StepGridCoordinator`.
- Define `StepSelectionModel` lifetime rules.
- Resolve macro-layer write-path ambiguity.
- Confirm copy/paste scope.
- State the rotary row trigger-layer behavior.
- Set a maximum editable-layer count before overflow handling is needed.
