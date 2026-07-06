---
feature: drum-kit-matrix-sound-prep
status: accepted
stage: plan
created: 2026-07-05
sources:
  - docs/roadmap/drum-kit-matrix-sound-prep/spec.md
---

# Drum Kit Matrix Sound Prep Plan

## Slice Boundary

Implement one bounded UI pass over the drum-kit Tracks and kit-matrix surfaces:

1. Reconfirm current kit-track grid, kit matrix, and drum-part Sound seams.
2. Preserve or restore compact kit-track and part-cell grammar.
3. Preserve or restore compact kit-matrix header/pattern/part-row grammar.
4. Preserve or restore distinct drum-part no-sound-source, sampler,
   missing-sample, and AU-source states.
5. Capture evidence and run the UX canon gate.

Stop if the work requires AU runtime lifecycle changes, mixer/routing redesign,
or broad non-kit header compression.

## Step 1: Reconfirm Current State

Before editing, inspect the current code paths and note any drift in build
evidence:

- `Sources/UI/TracksMatrixView.swift` for kit cells, part cells, and inline
  expanded kit behavior.
- `Sources/UI/DrumGroup/DrumKitMatrixView.swift` and extensions for the kit
  header, matrix, tab selector, accordion, and capture/state rows.
- `Sources/UI/SamplerDestinationWidget.swift` and any drum-kit Sound routing
  helper for `.none`, `.sample`, `.auInstrument`, orphan/missing sample, and
  `.inheritGroup`.
- Existing visual scenario rows that already cover drum kit matrix, expanded
  kit row, add-kit modal, and sound states.

If current main already satisfies a listed acceptance criterion, record it and
avoid churn.

## Step 2: Tracks Grid Compression

Make the Tracks grid present kit tracks without extra wrapper chrome:

- Use one kit cell in the same grid as normal tracks.
- Show contained parts inside the collapsed cell only as compact indication.
- Keep expand/collapse inside the kit cell.
- When expanded, render the kit cell followed by normal part cells in the same
  grid flow.
- Keep accessibility identifiers or visual command hooks stable unless a rename
  is necessary and evidence is updated.

Verification: collapsed and expanded kit grid screenshots or deterministic
visual command evidence.

## Step 3: Kit Matrix Compression

Make the kit matrix read like the standard step editor at kit scale:

- Keep 16 columns and bar paging.
- Keep part names in a left column.
- Keep pattern slots at kit level in the compact header/top box.
- Remove any redundant `PATTERNS`, `KIT MATRIX`, group pattern, linked/mixed, or
  per-part pattern controls if they have reappeared.
- Keep Matrix / FX / Macros / Mixer selection on the shared segmented grammar.
- Delete no-longer-needed inline part headings or `Open full editor` affordance
  only when inline editing remains complete enough for this surface.

Verification: kit matrix screenshot or visual command evidence showing a
multi-part kit at default window size.

## Step 4: Drum-Part Sound Source

Make the Sound tab route and label the four important states distinctly:

- `.none`: neutral no-sound-source chooser with Sample and AU instrument
  actions.
- `.sample` with resolved sample: sampler panel, no persistent verbose AU strip.
- `.sample` with unresolved sample: missing-sample recovery state.
- `.auInstrument`: AU panel or AU readout with remove/change affordance.

Keep clear/remove behavior returning to `.none`. Keep `.inheritGroup` and
dormant filter behavior unchanged unless the current code already has a
documented safe path.

Verification: focused routing tests or view-model tests for the state routing,
plus screenshots/visual evidence for states reachable without human-present AU
validation.

## Step 5: Canon And Regression Checks

Required machine checks for any build loop promoted from this package:

- `scripts/diagnostics/ux-canon-lint.sh` on touched UI files, or full UI.
- Focused Swift tests covering sound-tab routing if that area changes.
- Any existing Tracks grid / drum-kit view tests touched by the implementation.
- Existing realtime/runtime ownership lints if product code changes touch
  destination mutation, routing, or engine-adjacent seams.

Do not run visual automation unattended unless
`SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1` is explicitly enabled. If closed,
record `capture-permission-or-focus` and provide the best non-TCC evidence.

## Exit Evidence

The build loop should leave compact evidence listing:

- acceptance criteria satisfied by existing code versus changed code;
- files changed;
- checks run and results;
- visual evidence paths or the explicit visual-evidence gap;
- any residual product-owner attention item, especially if a real AU acoustic
  pass is needed outside this PM scope.
