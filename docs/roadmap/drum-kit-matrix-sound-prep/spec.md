---
feature: drum-kit-matrix-sound-prep
status: accepted
stage: spec
created: 2026-07-05
sources:
  - .meta/multipass/state/bug-intake.md#G6
  - docs/bugs/20260618-135941-let-s-have-the-name-of-each-drum-part-to
  - docs/bugs/20260618-140108-drum-kit-step-sequencer-should-be-limite
  - docs/bugs/20260620-102115-patterns-and-kit-matrix-are-wasting-spac
  - docs/bugs/20260620-102248-also-kick-inline-part-controls-and-open
  - docs/bugs/20260620-203459-we-re-wasting-too-much-vertical-space-at
  - docs/bugs/20260622-124324-the-add-drum-kit-modal-needs-to-be-part
  - docs/bugs/20260624-161342-i-should-also-be-able-to-load-an-au-as-t
  - docs/bugs/20260626-095529-on-the-tracks-page-make-kit-tracks-show
  - docs/bugs/20260629-101345-drum-part-sound-source-empty-vs-none-and-load-au-affordance
  - docs/bugs/20260704-153522-the-top-section-of-slicer-normal-track-k
  - docs/ux-canon.md
---

# Drum Kit Matrix Sound Prep Spec

## Purpose

This package defines one builder-ready pass for the Tracks drum-kit surface:
make kit tracks and their parts read with the compact track grammar, remove
remaining kit-matrix waste, and make each drum part's sound-source state clear.

The pass is a UI/product-contract cleanup over existing drum-kit behavior. It
does not create a new drum-kit architecture, a broad header-compression lane, a
mixer/routing redesign, or an AU runtime safety program.

## Product Contract

### Kit Track In The Tracks Grid

- A kit track appears in the main Tracks grid like a normal track-sized cell.
- Collapsed kit cells show enough contained-part indication to be useful at a
  glance, without a surrounding group wrapper, title band, linked badge, shared
  destination prose, or extra section chrome.
- Expand/collapse is an affordance inside the kit cell.
- When expanded, the kit cell and its drum-part cells sit in the same grid flow:
  kit first, parts after it, no outer wrapper.
- Part cells should use the normal track-card grammar where possible, including
  comparable sizing, selection, and compact state treatment.

### Kit Matrix

- The kit matrix remains a 16-column step editor with the normal-track step
  primitives and a bar pager for later bars.
- Drum part names render in a fixed left column so more part rows remain visible.
- Pattern selection is kit-level only for this version. Do not reintroduce
  per-part pattern pills, linked/unlinked state, mixed badges, or re-link
  controls.
- Pattern slots live in the compact kit header/top box, not in a separate
  repeated panel below.
- Remove redundant section titles such as `PATTERNS` or `KIT MATRIX` where the
  surrounding tab/header already owns that context.
- Remove standalone inline-part headings and an `Open full editor` escape if the
  inline part controls already provide the editing surface.
- The Matrix / FX / Macros / Mixer selector uses the shared segmented grammar
  already used by comparable track surfaces.

### Drum Part Sound Source

- A drum part has one visible sound-source decision: Sample or AU instrument.
- `.none` renders as no sound source with compact Sample and AU instrument
  choices. It must not render as a missing sampler.
- A genuine `.sample` with a missing library item renders as a missing-sample
  recovery state. Reserve recovery actions such as replacing with the first
  available sample for that state only.
- A working sampler part does not carry a persistent verbose `Load AU...`
  description strip. Changing to AU should be a compact, obviously clickable
  action in the sound-source choice model.
- An AU instrument part renders as an AU sound-source panel with clear remove or
  change affordance, but this pass only specifies the surface contract.
- Clearing a sampler or AU part returns the part to the no-sound-source chooser.
- `.inheritGroup` behavior is not redesigned in this pass.
- A part filter may remain dormant-but-stored when the part uses AU; this pass
  must not invent new filter/FX behavior.

## Out Of Scope

- General slicer, normal-track, or audio-track header compression beyond using
  the already-compressed drum-kit shell as comparison.
- Mixer strips, sends, routing, kit FX, or per-part FX redesign.
- AU runtime safety, AU hosting lifecycle, preset application/removal while
  playing, sampler-to-AU acoustic validation, or engine hard-rule changes.
- Scenes IA, scene perform behavior, phrase/global-apply polish, or Track
  Perform mini-cell direct-selection work.
- Bug status updates or build-loop promotion.

## UX Canon Requirements

- The header owns shared context; cells do not repeat `KIT`, `PATTERN`, `SOUND`,
  or equivalent shared labels in every cell.
- The whole cell is the control where a grid cell represents a selectable or
  toggled state.
- No explainer prose on working surfaces. Use compact labels and tooltips.
- Same-kind grid cells keep comparable dimensions and step primitives.
- Use `StudioTheme`, `StudioMetrics`, `StudioTypography`, and shared segmented
  components; no system-grey escapes or translucent accent fills.
- Labels must fit at minimum supported window width without clipping or vertical
  letter stacks.
- If the part list exceeds the visible space, it scrolls with themed treatment.

## Acceptance Criteria

AC1. A collapsed kit track appears as one normal-sized grid cell with contained
part indication and no group wrapper chrome.

AC2. Expanding the kit shows kit and part cells inline in the same Tracks grid,
with the expand/collapse affordance remaining in the kit cell.

AC3. The kit matrix shows 16 steps per row using the normal step primitives and
keeps the bar pager for later bars.

AC4. Drum part names stay in a left column and at least the current captured
multi-part kit remains scan-friendly without moving names above rows.

AC5. Kit-level pattern slots sit in the compact header/top box; no standalone
pattern-title panel, group-pattern row, linked/unlinked controls, mixed badge,
or per-part pattern pills return.

AC6. The kit matrix and related tab selector do not show redundant title bands
or inline part headings that repeat the active context.

AC7. `.none` drum-part sound state shows a distinct no-sound-source chooser
with Sample and AU instrument options.

AC8. Missing-sample recovery appears only for a real sample destination with an
unresolved sample.

AC9. The AU choice is compact and clickable, not an always-on descriptive strip
under every sampler.

AC10. Clearing sampler or AU sound returns to the no-sound-source chooser
without changing kit membership.

AC11. The pass runs `scripts/diagnostics/ux-canon-lint.sh` for touched UI files
or for all UI if the build loop prefers the full canon gate.

AC12. The build evidence includes current screenshots or deterministic visual
evidence for collapsed kit cell, expanded kit cells, kit matrix, no-sound-source
chooser, missing-sample recovery, sampler part, and AU part if reachable without
human-present AU validation.

## Non-Goals And Safety Notes

Builders may touch the SwiftUI surfaces and view-model routing needed for this
contract. They must not change audio-engine invariants to satisfy the AU
affordance. Real AU instantiation and acoustic behavior remain human-present
validation outside this PM pass.
