---
feature: drum-kit-matrix-sound-implementation-prep
status: ready-for-build-loop-promotion
stage: implementation-handoff
created: 2026-07-06
sources:
  - docs/roadmap/drum-kit-matrix-sound-implementation-prep/spec.md
  - docs/roadmap/drum-kit-matrix-sound-implementation-prep/plan.md
  - .meta/multipass/state/bug-intake.md#G5
---

# Drum Kit Matrix Sound Implementation Handoff

## Purpose

This handoff packages the remaining G5 Drum Kit / Kit Matrix / Drum Part Sound
work into one bounded builder slice. It is ready to promote into a build loop,
but this PM artifact does not create that loop, route a builder, open a
worktree, merge, or update bug statuses.

## Starting Point

Use `build/drum-kit-matrix-sound-prep` only as closed seam evidence. It
accepted current-main behavior for flat kit cells, compressed kit matrix, and
distinct drum-part Sound routing, with visual evidence gated by permissions.
It did not claim the whole G5 feature-follow-up was implemented.

## Builder Boundary

Implement only:

- add-drum-kit modal cleanup and kit-page Add Part affordance;
- matrix and drum-part visual compression where current main still violates G5;
- preservation/verification of distinct Sound source states plus the July 7
  sampler Sound-page correction;
- kit-local FX, Macros, and Mixer visual consistency.

Do not broaden into:

- AU runtime safety, preset behavior, removal while playing, or real-AU acoustic
  validation;
- broad mixer/FX redesign;
- slicer/header compression;
- Scenes IA;
- Track/Phrase Perform interaction;
- generator-mode drum-part capture, Euclidean mono generator controls, or
  modifier-removal work for drum-part generator mode;
- kit capture/history/save interaction redesign;
- process-resolution closeout for bugs already fixed.

## First Builder Move

Start with a read-only current-main classification note:

| Bucket | Expected Examples |
|---|---|
| Already satisfied | flat kit grid, 16-step kit matrix, left part names, removed old redundant titles, distinct `.none` Sound chooser |
| Implementation gap | July 5 add-kit modal, kit-page Add Part, grey drum-part rows, stable larger top-aligned drum-part names with grey subtext removed, sampler waveform restored, bottom AU-load button removed, config-to-macros button removed, side-by-side dashed Sample/AU empty chooser, kit macros copy/background, kit mixer/routing consistency |
| Process only | bug folders with resolved-status text but no `resolution.md` |
| Out of scope | human-present AU validation, AU runtime safety, broad mixer/FX redesign, generator-mode drum-part capture/control additions, kit capture/history/save redesign |

Then edit the smallest kit-local surfaces needed to satisfy `spec.md`.

## Required Evidence

Before completion, provide:

- G5 classification after implementation;
- focused tests for changed creation/source-routing behavior;
- `scripts/diagnostics/ux-canon-lint.sh` result;
- visual evidence or explicit `capture-permission-or-focus` gap for add-kit
  modal, kit page/Add Part, kit matrix part rows, Sound states, FX, Macros, and
  Mixer/Routing;
- explicit July 7 classification separating accepted part-name/Sound-page
  deltas from generator-mode capture and kit capture/history/save follow-up
  scope;
- confirmation that no AU runtime/acoustic claim was made.

## Product-Owner Attention

No product-owner decision is needed to promote this builder slice. The default
product contract is clear: the kit surface should be compact, kit-level patterns
stay global, part rows stay visible and high-contrast, Sound source states stay
distinct, and kit-local FX/Macros/Mixer should match comparable app grammar.

Ask only if implementation uncovers a new product choice, such as whether empty
kits should auto-create a first part, or if a UI repair would require changing
AU runtime behavior.
