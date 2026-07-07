---
feature: drum-kit-matrix-sound-implementation-prep
status: accepted
stage: plan
created: 2026-07-06
sources:
  - docs/roadmap/drum-kit-matrix-sound-implementation-prep/spec.md
---

# Drum Kit Matrix Sound Implementation Prep Plan

## Slice Boundary

Implement one compact kit-surface cleanup pass over the remaining G5
implementation gaps:

1. Reconfirm current-main coverage from the closed seam check.
2. Fix the add-drum-kit modal and kit-page Add Part affordance.
3. Tighten drum-part row contrast and kit-matrix global-pattern consistency.
4. Preserve and verify drum-part Sound source routing.
5. Align kit FX, Macros, and Mixer visuals with comparable track/scene surfaces.
6. Record bug-gap classification and evidence.

Stop if the work would require AU runtime changes, broad mixer redesign,
non-kit header compression, Scenes IA, or Track/Phrase Perform changes.

## Step 1: Baseline Seam Check

Before editing, inspect the current code and evidence paths:

- `Sources/UI/TracksMatrixView.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView+Header.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView+KitTabs.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift`
- `Sources/UI/SamplerDestinationWidget.swift`
- add-drum-kit sheet code and visual scenario commands for `02d`.

Classify each G5 bug as one of:

- already satisfied by current main;
- implementation gap in this slice;
- process-resolution metadata only;
- intentionally out of scope.

Do not edit code that already satisfies the spec just to restate old work.

## Step 2: Add Drum Kit Entry Flow

Update the add-drum-kit modal so it behaves like a compact creation surface:

- remove routing choice and default to the correct new kit bus;
- remove duplicate `Sounds` and `Patterns` title-line chrome;
- move pattern/template choice to the kit page if it is still duplicated in the
  modal;
- replace ambiguous checkbox/disabled-button states with compact, labeled,
  usable controls;
- add or expose kit-page Add Part when a kit has zero parts.

Verification: focused UI/view-model tests if state changes are introduced, plus
visual evidence for the add-kit modal and empty-kit kit page when capture is
allowed.

## Step 3: Matrix And Drum-Part Visual Compression

Preserve the seam-check matrix contract while addressing remaining visual
complaints:

- keep 16 steps, bar pager, and left part-name column;
- prevent per-part pattern mismatch UI from returning;
- remove low-contrast grey part-row backgrounds;
- keep labels and controls fitting at supported minimum width;
- keep capture cleanup untouched unless current code regressed against its
  resolved-status contract.

Verification: screenshots or deterministic visual status for the default kit
matrix and a value/layer state such as velocity.

## Step 4: Drum-Part Sound Source

Treat the Sound tab as a state-routing preservation area:

- retain distinct `.none`, resolved sampler, missing sample, and AU panels;
- keep Sample and AU actions compact and obviously clickable;
- ensure clear/remove returns to `.none`;
- avoid real-AU acoustic claims and do not alter engine hard-rule surfaces.

Verification: existing or new routing tests for any changed state path. If the
AU panel is visible without instantiating a third-party AU, capture it; otherwise
record the human-present AU evidence gap.

## Step 5: Kit FX, Macros, Mixer Consistency

Apply only kit-local visual consistency repairs:

- make Kit FX empty/populated/add modal behavior match the comparable Scene/Track
  FX grammar;
- remove `kit-wide macro sweeps` prose and align macro rotary styling;
- align the kit Mixer/Routing visual treatment with other scene-routed tracks;
- do not redesign sends, routing, mixer strips, or effect architecture.

Verification: visual evidence for Kit FX, Macros, and Mixer tabs, or an explicit
visual automation gate note.

## Required Checks

Run these when code changes are made:

- `scripts/diagnostics/ux-canon-lint.sh` for touched UI files or the full UI.
- Focused Swift tests for changed drum-kit creation or sound-source routing.
- Existing Tracks/drum-kit UI tests touched by the implementation.
- Realtime/runtime ownership lints only if the change touches destination
  mutation, routing, or engine-adjacent code.

Do not run Peekaboo, screenshot/app-control scenarios, `osascript`, or other
TCC-gated visual automation unless the environment explicitly enables it. If
closed, record `capture-permission-or-focus`.

## Exit Evidence

The build loop should leave a compact evidence note with:

- files changed;
- checks run and results;
- visual paths or explicit visual evidence gap;
- G5 bug classification after the slice;
- any remaining process-resolution-only bugs;
- explicit statement that no AU runtime safety or human-present AU validation
  was claimed.
