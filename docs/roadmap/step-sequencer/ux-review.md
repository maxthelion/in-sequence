# Step Sequencer UX Review

Reviewed: 2026-04-29
Prototypes reviewed: `prototypes/variant-a-inline-column.html`, `prototypes/variant-b-floating-popover.html`
Feedback applied: `feedback/20260430-103803-prototypes-feedback.md`

---

## Summary of Feedback

The feedback rejects both prototyped editing surfaces (inline docked column and floating popover) and
redirects the design toward two clarifying ideas:

1. **No popup or panel on step selection.** The step cell itself should be the editing surface.
   The inner content of the cell should change depending on the active layer. For a velocity layer
   the bar inside the cell should be directly draggable. Nothing external should appear.

2. **Cell content must be track-type-aware, not just layer-aware.** A slicer step should visually
   highlight which slice is assigned. A chord-generator step should highlight the chord. The two
   prototypes treated all tracks as generic note-grid sequences and failed to show these
   specialised representations.

3. **Try a rotary-above variant.** When one or more steps are selected, the layer controls in the
   row above the step grid (the layer tabs / macro row) should become rotary controls that can be
   turned to modify the value for those steps. This is a meaningful departure from both existing
   variants and should be prototyped separately.

4. **Context is the central design problem.** The prototypes reveal the structural challenge:
   "step" means something different across track types. A regular note-grid track, a slicer track,
   and a chord-generator track each need a different cell representation. The current prototypes
   show only the generic case and do not make this variation legible to reviewers.

---

## What Works in the Existing Prototypes

### Shared cell visual language
Both variants correctly unified the four-state cell (active / inactive / playing / selected) into a
single primitive. The colour conventions — dark fill for active, green border for playing, amber
border/inset for selected — are clear and compose without ambiguity. This direction should be kept.

### Layer-driven cell content switching
Both prototypes switch the interior of each cell when the layer tab changes (toggle dot, vertical
bar, label). This is the correct underlying idea. The feedback confirms this but wants the interior
to be directly interactive rather than opening an edit surface elsewhere.

### Step number row and batch action bar
The step-number row and the batch action bar (clear / copy / paste) are both sensible and not
rejected by the feedback. These can carry forward.

### Interaction budget
Both variants achieve the primary goal in three interactions. The feedback does not dispute this;
it disputes which interactions those are. The new direction reduces the count: left-click toggles,
drag on a bar cell edits the value, rotary on the layer row edits selected steps. No right-click
panel required.

---

## What Fails

### Popup / panel editing surface (both variants)
The core failure in Variant A (docked column) and Variant B (floating popover) is that selecting
a step opens a secondary editing panel. The feedback is explicit: this is unwanted. The panel
approach also has practical problems — the column widens the layout and the popover occludes
adjacent cells. Both are eliminated.

### Generic cell content independent of track type
Both prototypes use a single set of cell variants (dot, bar, label) that do not account for track
type. A slicer step needs to show which slice is assigned (e.g., a small slice index label or
highlighted slice strip). A chord-generator step needs to show which chord is active (e.g., a
chord name, or highlighted chord-degree dots). The existing variants show none of this and
therefore cannot be used as the basis for the unified primitive without track-type branching.

### No rotary-above pattern explored
Neither prototype attempted the "rotary controls above selected steps" idea described in the
original notes and now made explicit in the feedback. This is a first-class alternative to
dragging inside the cell and may be more appropriate for coarse value adjustment across multiple
selected steps.

### Layer tabs remain external to the cell
In both prototypes the layer tabs sit above the grid as a tab bar. The feedback hints that, at
minimum when steps are selected, these layer controls should transform into editable rotary
controls. The prototypes do not explore that transition.

---

## Checklist Results (against `docs/html-prototype-guidelines.md`)

| Criterion | Variant A | Variant B |
|---|---|---|
| Single-file, no build steps | Pass | Pass |
| Monochrome base, semantic color only | Pass | Pass |
| Stub regions clearly marked | Pass | Pass |
| Real interactions on primary path | Pass | Pass |
| Fixture data is adversarial / varied | Pass (16 steps, varied velocity/chance) | Pass |
| Interaction budget stated and verified | Pass (3 steps) | Pass |
| Variants are strategically different, not cosmetic | Partial — the column vs popover distinction is real but the feedback reveals both are wrong-direction rather than right-direction alternatives | Same |
| Reviewer cannot mistake for production | Pass | Pass |

The checklist failures are not process failures but selection failures: the two variants
explored a dimension (where the edit panel lives) that the feedback now eliminates.

---

## Recommended Direction

### Direction: In-Cell Editing with Rotary Layer Row

Do not build a third variant that re-explores popup vs panel. Instead build two new prototypes
that each eliminate the secondary panel entirely:

**Variant C — In-Cell Drag Editing (no panel)**

- Left-click: toggles active state (unchanged).
- On a value layer (velocity, chance): the interior bar is directly draggable vertically.
  Drag up/down changes the value. No panel opens.
- On a toggle layer (steps): the dot represents on/off. No draggable interior.
- On an option layer (slicer, chord): the cell shows a compact representation of the assigned
  option (slice label or chord name). Clicking cycles through options.
- Selected step(s) highlighted by amber border (unchanged).
- Batch action bar remains (unchanged).
- The layer tabs above the grid remain tabs (not rotaries) — this is the simpler sub-case.

**Variant D — Rotary Layer Row (selected-steps mode)**

- Same as Variant C for normal interaction.
- When one or more steps are selected, the layer tab row transforms. Each layer label gains a
  rotary control (small circular dial or arc-scrubber). Turning the rotary changes that layer's
  value for all selected steps simultaneously.
- The rotary is visible only while steps are selected; on deselection the row reverts to tabs.
- This explores the "controls above selected steps become editable" idea from the original notes
  in a more physically direct way than the docked column.

**Track-type branching that must appear in both variants:**

| Track type | Step cell content |
|---|---|
| Note grid (trigger layer) | Dot (on) or empty (off) |
| Note grid (velocity layer) | Vertical bar proportional to velocity, draggable |
| Note grid (chance layer) | Vertical bar proportional to chance %, draggable |
| Slicer track | Slice index label or small highlighted segment indicator |
| Chord generator | Chord name or highlighted chord-degree dots |

At minimum Variant C and D should show the slicer and chord-generator cell variants as stubbed
static states alongside the draggable note-grid cells, so reviewers can evaluate whether the
shared primitive scales to those contexts.

---

## Questions and Required Follow-Up

1. **Screenshots:** The feedback mentions "there are some screenshots in this directory." No image
   files were found under `docs/roadmap/step-sequencer/`. The `artifacts.md` file contains a
   text summary of four screenshots from a planning conversation. If the actual images are
   available they should be placed in `docs/roadmap/step-sequencer/screenshots/` and reviewed
   before building Variant C and D, as they may show existing UI that the new prototype should
   reference or preserve.

2. **Drag gesture vs tap-cycle for value layers:** The feedback says bars should be "draggable."
   In a touch context dragging inside a 32×44 pt cell is tight. Variant C should prototype a
   fallback: tap the cell to select it, then use a drag zone that expands to full-cell-width on
   selection. This needs a decision before implementation.

3. **Rotary control type:** For Variant D, what does the rotary look like? Options: (a) a small
   arc slider inline with the layer label, (b) a numeric scrubber field that drag-scrubs, (c) a
   miniature dial. The choice affects how many layers can fit in the row simultaneously. This
   should be visible in the prototype so the user can react to it.

4. **Chord-generator step cell:** The feedback references "a chord step in the chord generator
   needs to highlight the chord." Chord data is not present in the current step model
   (`ClipContent.noteGrid` stores per-step notes, not chord abstractions). If chord identity is
   tracked separately by the chord-generator track type, the cell representation needs access to
   that mapping. This is a model gap that may need to be flagged in the spec before prototyping
   can be finalised.

5. **Multi-step rotary semantics:** When multiple steps with different values are selected and a
   rotary is turned, does it set an absolute value for all, or apply a relative delta? The
   feedback does not specify. Variant D should prototype one assumption explicitly and label it
   as such.

---

## Next Action

Build `prototypes/variant-c-in-cell-drag.html` and `prototypes/variant-d-rotary-layer-row.html`
incorporating track-type branching (note-grid, slicer, chord-generator cells as static stubs)
and eliminating any secondary panel. After user review of those variants, write `spec.md`.
