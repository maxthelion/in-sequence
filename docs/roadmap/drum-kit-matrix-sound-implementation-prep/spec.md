---
feature: drum-kit-matrix-sound-implementation-prep
status: accepted
stage: spec
created: 2026-07-06
sources:
  - .meta/multipass/state/bug-intake.md#G5
  - .meta/multipass/runtime/loops/build/drum-kit-matrix-sound-prep/decide/2026-07-06T15-47Z-accept-seam-check-no-builder.md
  - docs/roadmap/drum-kit-matrix-sound-prep/spec.md
  - docs/bugs/20260705-150256-let-s-leave-out-the-routing-part-it-shou
  - docs/bugs/20260705-195311-get-rid-of-kit-wide-macro-sweeps-text-ma
  - docs/bugs/20260705-195340-this-is-now-inconsistent-with-other-trac
  - docs/bugs/20260705-195817-this-needs-to-be-less-grey-and-low-contr
  - docs/bugs/20260623-131730-i-think-we-get-rid-of-this-view-and-capt
  - docs/bugs/20260623-131943-there-s-stuff-here-that-doesn-t-represen
  - docs/bugs/20260623-132043-add-kit-effect-modal-blocks-the-view
  - docs/bugs/20260624-161342-i-should-also-be-able-to-load-an-au-as-t
  - docs/bugs/20260629-101345-drum-part-sound-source-empty-vs-none-and-load-au-affordance
  - docs/bugs/20260707-110157-on-the-kit-view-the-name-of-the-drum-par
  - docs/bugs/20260707-110758-the-sound-page-for-a-sampler-is-missing
  - docs/bugs/20260707-110401-include-the-generator-mode-for-drum-part
  - docs/bugs/20260707-111802-the-capture-page-for-a-kit-is-quite-bugg
---

# Drum Kit Matrix Sound Implementation Prep Spec

## Purpose

This package defines one builder-facing implementation slice for the remaining
`G5: Drum Kit / Kit Matrix / Drum Part Sound` bugs after the closed
`build/drum-kit-matrix-sound-prep` seam check.

The previous prep package and seam check are current-main evidence, not a
whole-feature implementation claim. A builder should preserve behavior already
satisfied there and repair only the remaining kit-page and drum-part Sound
violations.

## Current-Main Baseline To Preserve

Treat these as already covered unless fresh evidence contradicts them:

- kit tracks render in the Tracks grid without the old group wrapper;
- expanded kit parts appear inline with the kit cell;
- kit matrix keeps 16 steps, bar paging, kit-level pattern slots, and left
  part-name rows;
- redundant `PATTERNS`, `KIT MATRIX`, inline-part headings, kit FX subtext,
  Macros subtext, and Mixer subtext were removed;
- `.none`, sampler, missing-sample, and AU-source drum-part Sound routing has
  a machine-verifiable split;
- kit capture cleanup has resolved-status text but still needs process-closeout
  evidence outside this implementation slice.

## Builder Slice Contract

### Add Drum Kit Modal And Kit Page Creation

- The add-drum-kit modal does not expose routing as a user decision in this
  slice. New kits default to the correct current bus.
- Remove unnecessary `Sounds` and `Patterns` title lines from the modal.
- Pattern/template choice belongs on the kit page, not as duplicate modal
  chrome.
- The modal must make empty-kit creation understandable: no unexplained
  disabled primary action or unlabeled checkbox.
- The kit page exposes a clear Add Part action, so creating a kit with no parts
  is a legitimate starting point.

### Drum Kit Matrix And Part Rows

- Keep the compressed matrix grammar from the seam check.
- Drum-part rows must stay high-contrast and visually light: no low-contrast
  grey slab backgrounds around the part controls or row content.
- Part names remain visible in the left column; value/layer states do not push
  names above rows or into vertical clipping.
- July 7 intake correction: the drum-part name in kit view belongs near the top
  of the part row, larger than secondary labels, so expanding the part does not
  move the name. Remove the grey explanatory subtext from that row.
- Pattern mismatch, per-part pattern state, and similar controls that contradict
  kit-level global patterns must not reappear.

### Drum-Part Sound Source

- Preserve the distinct Sound states:
  `.none` means no sound source, `.sample` with a valid sample is a sampler,
  `.sample` with a missing item is recovery, and `.auInstrument` is an AU panel.
- July 7 intake correction: the sampler Sound page shows the sampler waveform.
  It does not show the bottom AU-load button, and it does not show the config
  button next to play that navigates to macros.
- Empty Sound source uses two side-by-side dashed plus boxes for Sample and AU.
  Remove the literal `no sound source` prose.
- Clearing sampler or AU still returns to the no-sound-source chooser.
- `.inheritGroup` and dormant filter behavior are not redesigned.

### July 7 Intake Classification

- Accepted into this builder slice: drum-part name placement, removal of grey
  row subtext, sampler waveform restoration, removal of the bottom AU button,
  removal of the play-adjacent config-to-macros button, and the side-by-side
  dashed Sample/AU empty chooser.
- Follow-up / separate PM scope: generator-mode capture coverage for drum
  parts, Euclidean mono controls for drum-part generator mode, removal of the
  modifier aspect from that generator surface, and the request to remove the
  word `source`.
- Follow-up / separate PM scope: kit capture page history/navigation/save
  behavior, including mini clip-history bar, save-to-pattern pulsing, history
  selection display, and capture-page close/navigation grammar.
- The follow-up items above are not silently added to this builder acceptance
  gate. They need separate PM classification or an explicit build-loop route.

### Kit FX, Macros, Mixer, And Modal Consistency

- Kit FX uses the same visible grammar as comparable Scene/Track FX empty and
  populated states, including non-blocking add-effect flow where feasible.
- Add-kit-effect modal behavior must not obscure the surface in a way that
  prevents useful capture or review of the underlying kit state.
- Kit Macros remove `kit-wide macro sweeps` copy and use the same rotary grammar
  and background treatment as comparable macro views.
- Kit Mixer/Routing appearance stays consistent with other tracks that have
  scene routing; do not start a broad mixer redesign.

## Out Of Scope

- AU runtime safety, preset reliability, third-party AU acoustic validation, or
  engine lifecycle changes.
- Broad mixer/FX redesign beyond kit-surface consistency.
- Slicer/header compression, normal-track setup compression, Scenes IA,
  Track/Phrase Perform interaction, or Phrase capture changes.
- Bug-folder status updates, bug-intake edits, build-loop promotion, merge,
  rebase, push, or worktree cleanup.

## Acceptance Criteria

AC1. Add-drum-kit modal omits routing, removes duplicate title-line chrome, and
lets the user create an empty kit without ambiguous disabled controls.

AC2. Kit page exposes an Add Part action for an empty or existing kit.

AC3. Kit matrix remains compressed: 16 steps, left part-name column, bar pager,
kit-level patterns, and no per-part pattern mismatch controls.

AC4. Drum-part rows and matrix layers remove low-contrast grey backgrounds while
remaining legible at the supported minimum width.

AC5. Drum-part Sound keeps distinct `.none`, sampler, missing-sample, and AU
states, restores the sampler waveform, removes the bottom AU-load and
config-to-macros buttons, uses side-by-side dashed Sample/AU empty-choice boxes,
and keeps clear return-to-none behavior.

AC6. Kit FX empty/populated states and add-effect modal behavior match the
existing Scene/Track FX grammar closely enough for visual review.

AC7. Kit Macros use consistent rotaries and no `kit-wide macro sweeps` prose or
grey panel background.

AC8. Kit Mixer/Routing state is visually consistent with other scene-routed
tracks without changing routing architecture.

AC9. The builder records which G5 reports are implementation-fixed versus
already satisfied by current main or only missing process-resolution metadata.

AC10. Evidence includes focused tests for changed routing/state decisions, a UX
canon lint, and visual evidence or an explicit `capture-permission-or-focus`
gap for add-kit modal, kit matrix/part rows, Sound states, FX, Macros, and
Mixer/Routing.

AC11. Evidence classifies July 7 generator-mode capture and kit
capture/history/save notes as follow-up or separate PM scope unless a later
accepted artifact explicitly expands the builder slice.
