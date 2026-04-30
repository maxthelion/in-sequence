---
verdict: accepted
selected_prototype: variant-d-rotary-layer-row.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/variant-a-inline-column.html
  - prototypes/variant-b-floating-popover.html
  - prototypes/variant-c-in-cell-drag.html
  - prototypes/variant-d-rotary-layer-row.html
feedback_applied: feedback/20260430-103803-prototypes-feedback.md
---

# Step Sequencer UX Review — 2026-04-30

## Context

Variants A and B were rejected in the previous review cycle
(`ux-reviews/ux-review-2026-04-29.md`) because both opened a secondary editing
panel on step selection. The user's feedback was explicit: no popup, the cell
is the editing surface, value bars must be directly draggable, and a
"rotary-above" variant must be prototyped. Variants C and D were built to
address this. This review evaluates all four variants and selects a direction.

---

## Checklist Results

The checklist columns below use: Pass / Fail / Partial / N/A.

| Criterion | A | B | C | D |
|---|---|---|---|---|
| Single-file, no build steps | Pass | Pass | Pass | Pass |
| Monochrome base, semantic color only | Pass | Pass | Pass | Pass |
| Stub regions clearly marked | Pass | Pass | Pass | Pass |
| Real interactions on primary path | Pass | Pass | Pass | Pass |
| Fixture data is adversarial / varied | Pass | Pass | Pass | Pass |
| Same fixture data across compared variants | N/A | N/A | Pass | Pass |
| Interaction budget stated and verified | Pass | Pass | Pass | Pass |
| Variants are strategically different, not cosmetic | Fail (same failure mode, different surface) | Fail | Pass | Pass |
| Reviewer cannot mistake for production | Pass | Pass | Pass | Pass |
| Track-type-aware cell content shown | Fail | Fail | Pass | Pass |
| No secondary panel on step selection | Fail | Fail | Pass | Pass |
| Value bars directly draggable in cell | Fail | Fail | Pass | Pass |
| Rotary-above pattern explored | Fail | Fail | Fail | Pass |

Variants A and B fail on three of the new criteria that emerged from the
feedback. Variants C and D pass all criteria. They differ in one meaningful
dimension: how multi-step value editing is offered.

---

## Per-Variant Assessment

### Variant A — Inline Column (archived)

The docked column expands to the right of a selected step and shows layer
controls. The structural problem is that this requires layout width to
accommodate the column, and it is a secondary surface — the cell is not the
editor. Rejected in the previous cycle and not reconsidered here.

### Variant B — Floating Popover (archived)

The popover floats above the selected step. It occludes adjacent cells, still
opens a secondary surface, and is the wrong interaction model per the user's
feedback. Rejected in the previous cycle and not reconsidered here.

### Variant C — In-Cell Drag (no panel)

Addresses the core feedback: the cell is the editing surface with no panel.

**What works:**

- Left-click toggles active state cleanly (trigger layer).
- Value layers (velocity, chance) render a vertical bar that is draggable
  inside the cell. Drag feedback is immediate. The `↕` drag hint is visible
  and appropriately subtle. The interaction budget is 2: click layer tab, drag
  bar.
- Option layers (slicer, chord) cycle on left-click. The slice segment strip
  correctly highlights the assigned segment. Chord cells show Roman-numeral
  label and scale-degree dots, satisfying the "highlight the chord" request.
- The four-state cell (active, inactive, playing, selected) composes cleanly
  with no visual ambiguity. All four states are visible simultaneously; the
  playing+selected compound state (amber outline, green inset shadow) is
  distinguishable.
- The batch action bar (clear, copy, paste) appears on selection and hides on
  deselection without layout shift.
- Track-type switching (Note Grid / Slicer / Chord Gen) correctly changes the
  layer tabs and cell representation. This satisfies user story 6 directly.
- Adversarial fixture data is used across all three track types (varied
  velocities, 8-slice indices, 12 chord options including 7ths and
  diminished).
- The `expand-hint` annotation (dashed amber border on selected cell) signals
  the expanded drag zone idea for touch without implementing it, which is
  appropriate for a prototype.
- Stub layers (Macro 1, stubbed velocity/chance on slicer) show an alert and
  are visually distinct.

**What fails or is limited:**

- Multi-step value editing requires either (a) selecting steps first then
  dragging a bar on one of them, or (b) selecting steps and dragging any
  selected cell's bar. The behavior is implemented and labeled, but the
  multi-step edit path is not visually obvious. There is no UI signal that
  dragging on a selected step will affect all selected steps. A reviewer who
  does not read the annotation will not discover this.
- The layer tab row stays static during selection. There is no visual cue that
  the layer context has "activated" for editing the selected steps. The tab row
  and the selection feel disconnected.
- For slicer and chord layers, multi-step editing would require cycling each
  step individually (click on each cell). There is no batch path for option
  layers in Variant C.
- The chord cell's scale-degree dots are 5px circles with a 3px gap at 40px
  cell width. Seven dots across a 40px cell is tight. Reviewers should assess
  whether the dots are legible at actual sequencer scale.
- Copy and paste are stubs. This is appropriate for a prototype, but the user
  story requires them. The acceptance signal for story 5 is not fully
  verifiable in this prototype.

**User story coverage:**

| Story | Coverage |
|---|---|
| 1. Unified step cell primitive | Covered: same primitive across all three track types |
| 2. Step state legibility | Covered: all four states visible simultaneously |
| 3. Right-click step selection | Covered: right-click selects, layer tabs remain |
| 4. Multi-step selection | Covered: selection works; batch edit path exists but undiscoverable |
| 5. Contextual batch action bar | Partially covered: clear works; copy/paste stubbed |
| 6. Layer-driven cell control type | Covered: switching layer changes cell content type |

### Variant D — Rotary Layer Row (selected-steps mode)

Superset of Variant C. All of Variant C's behaviors are preserved. The
distinguishing feature: when any step is selected, the layer-tab row
transforms into a row of draggable SVG rotary controls, one per editable
layer. On deselection (or Escape), the row reverts to plain tabs.

**What works beyond Variant C:**

- The rotary row transition is the key innovation requested in the feedback.
  It makes the "controls above selected steps become editable" idea physically
  direct. Selecting a step immediately transforms the row — there is no
  ambiguity about which UI element to reach for.
- The SVG arc-dial rotary is visually clear. The amber arc fills proportionally
  to the value. The label and numeric value are readable inline with the dial.
- The "STEP EDIT" amber label on the rotary row signals the mode change
  without relying on color alone.
- Multi-step editing via the rotary is fully discoverable: select steps, the
  row changes, drag the rotary. The 3-interaction budget (select, see rotary,
  drag) is explicitly stated and correct.
- The absolute-vs-relative semantics question is made explicit in both the
  prototype annotation note and the interaction contract legend, exposing the
  open question to the user rather than silently choosing one. This is the
  right approach for a prototype.
- Slicer and chord layers are editable via rotary (snapping to integer index)
  as well as via in-cell click-cycle. This solves the batch option-layer
  editing gap in Variant C.
- The rotary updates the cell values live during drag — the bars and labels
  in the step grid update immediately, confirming multi-step application.
- The `active-layer-rotary` highlight (amber border on the rotary control for
  the active tab) maintains layer context even in selection mode.

**What fails or is limited:**

- The rotary's interaction is drag-based (ns-resize cursor, mousedown+mousemove).
  The drag sensitivity (`80px = full range`) is prototyped with a reasonable
  default but not tunable. For fine-grained values (e.g., velocity 64 vs 66)
  the required drag distance is small and precision is potentially difficult.
  This is a known open question, not a prototype defect.
- The trigger layer is correctly excluded from the rotary row ("No value
  layers" guard is present). However, when the active layer is `trigger` and
  steps are selected, the rotary row shows "No value layers" text only. The
  pattern of showing velocity/chance rotaries regardless of active layer
  would be more useful — but this may be an intentional design boundary and
  should be an explicit decision in the spec.
- At 56px minimum width per rotary, three rotaries (Steps excluded, two
  editable layers) fit comfortably in an 860px shell. At more than four
  editable layers (e.g., a track with macro layers added) the rotary row
  could overflow or wrap. The prototype uses `flex-wrap` which handles this
  gracefully, but a narrow viewport or a track with 6+ layers would crowd
  the row. This is a layout risk to flag in architecture.
- The chord dot legibility concern from Variant C also applies here, since
  cell rendering is shared.
- Copy and paste remain stubs — same gap as Variant C.
- No touch fallback is shown or annotated. Variant C documented the
  "tap-to-select, expand drag zone" touch concept; Variant D does not carry
  this annotation forward. This should be noted in the spec.

**User story coverage:**

| Story | Coverage |
|---|---|
| 1. Unified step cell primitive | Covered: same as Variant C |
| 2. Step state legibility | Covered: same as Variant C |
| 3. Right-click step selection | Covered: right-click selects, rotary row appears |
| 4. Multi-step selection | Fully covered: rotary row makes batch editing discoverable |
| 5. Contextual batch action bar | Same partial coverage as Variant C |
| 6. Layer-driven cell control type | Covered: rotary row also adapts per track-type layers |

---

## Head-to-Head: Variant C vs Variant D

| Dimension | C | D |
|---|---|---|
| No secondary panel | Pass | Pass |
| Track-type-aware cells | Pass | Pass |
| Single-step value edit discoverability | Good (drag bar in cell) | Good (same) |
| Multi-step value edit discoverability | Weak (undocumented in UI) | Strong (rotary row appears) |
| Batch option-layer editing (slicer/chord) | No | Yes (rotary snaps to index) |
| Interaction budget for multi-step edit | Implicit 2 steps | Explicit 3 steps |
| Layer row complexity | Low (tab row, no mode change) | Higher (tab/rotary mode switch) |
| Open question surfaced to user | Multi-step semantics unclear | Absolute vs relative explicit |
| Interaction budget for single step | 2 | 2 (unchanged) |

The rotary row is the more complete solution for the user stories. The mode
switch (tab row to rotary row) is the only additional cognitive cost, and the
prototype shows it is immediately legible — the amber "STEP EDIT" label and
the transformed controls signal the mode without any learning period.

---

## Recommendation

**Select Variant D (rotary layer row) as the direction for architecture and
spec.**

The reasons:

1. It directly implements the user's "rotary-above" request from the feedback.
2. It solves the multi-step discoverability gap that Variant C leaves open.
3. It handles batch editing for option layers (slicer slice, chord name) which
   Variant C has no path for.
4. The open question on absolute vs relative semantics is correctly surfaced in
   the prototype and must be resolved before spec.
5. The four-state cell primitive, layer-driven content switching, and batch
   action bar all carry forward from the earlier prototypes without change.

**Elements to carry forward from Variant C intact:**

- The four-state cell primitive and its color conventions.
- In-cell drag bars for single-step value editing (this remains the fast path;
  the rotary row is the selection-mode path).
- In-cell click-cycle for slicer and chord steps.
- The step number row above the grid.
- The batch action bar (clear / copy / paste).

**Open questions to resolve before or during architecture:**

1. **Absolute vs relative rotary semantics.** When multiple steps with different
   values are selected and a rotary is turned, does it set an absolute value or
   apply a relative delta? The prototype assumes absolute. This must be a
   deliberate product decision before spec.
2. **Active-layer vs all-layers rotary row.** When steps are selected, should
   the rotary row show only the currently active layer's control, or all editable
   layers simultaneously? Variant D shows all non-stub editable layers. This is
   the better approach for discovery but adds width pressure.
3. **Trigger layer and the rotary row.** When the active layer is "trigger" and
   steps are selected, no rotary is shown (boolean has no continuous value).
   Should the rotary row still appear with a "toggle all" action in place of
   a rotary? Or is the batch action bar's "Clear" button sufficient for this
   case?
4. **Touch gesture.** Variant C annotated a "tap-to-select, then drag zone
   expands" concept for touch. This concept was not carried into Variant D.
   Before spec, decide whether the touch path is in scope or deferred.
5. **Chord dot legibility at production scale.** Seven 5px dots across a 40px
   cell is tight. The spec must either confirm this is acceptable at actual
   sequencer scale or define a fallback representation (e.g., chord name label
   only when cell is narrow).
6. **Rotary row overflow at high layer counts.** A track with more than three
   editable layers could crowd the rotary row. The architecture and spec should
   define a maximum before overflow handling is needed (e.g., scroll, collapse,
   or a "more layers" affordance).

---

## Next Action

Advance to `write-architecture`. The selected direction (Variant D, with
Variant C's cell primitive carried forward) is clear enough to write
architecture guardrails. The six open questions above are inputs for the
architecture stage; questions 1 and 3 may also need user clarification before
the spec is final.
