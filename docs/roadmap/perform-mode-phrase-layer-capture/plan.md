---
feature: perform-mode-phrase-layer-capture
created: 2026-06-18
status: accepted builder-facing implementation plan
sources:
  - docs/roadmap/perform-mode-phrase-layer-capture/architecture.md
  - docs/roadmap/perform-mode-phrase-layer-capture/spec.md
  - docs/roadmap/perform-mode-phrase-layer-capture/reasoning-v3.md
  - docs/roadmap/perform-mode-phrase-layer-capture/prototypes/05-phrase-value-cell-system-v3.html
---

# Perform Mode, Phrase Layers, And Capture Plan

## Build Goal

Implement the phrase-first performance flow described by the V3 wireframe
without producing a half-old, half-new hybrid. The build should make phrase the
active context for transport, layer performance, scene performance, global
layer/value application, and phrase capture.

## Implementation Sequence

### 1. Revalidate Current Integration Points

Before editing, inspect the current code for:

- transport phrase state and current/next phrase ownership;
- phrase matrix and phrase page routing;
- track perform card layout and layer selector components;
- scene perform A/B/crossfader components;
- existing phrase cell mutation paths;
- existing runtime overlay/staging patterns;
- undo/dirty-state behavior for phrase edits.

Update the build-loop orientation if any of these have moved.

### 2. Add Or Confirm Phrase Navigation State

Make sure transport/session state can represent:

- current phrase;
- optional next phrase;
- phrase progress to the next boundary;
- Song mode arrangement-proposed next phrase;
- Free mode cue-selected next phrase.

Wire the transport display first so all later surfaces can be checked against
one phrase truth.

### 3. Add Phrase Perform Copy Boundary

Implement or adapt a temporary phrase copy/overlay:

- Perform Off writes to phrase baseline;
- Perform On writes to the live copy/overlay;
- dirty summary derives from overlay differences;
- Discard clears overlay;
- Capture writes overlay to a chosen phrase destination.

Keep document mutation, undo, and dirty behavior explicit. Do not let perform
overlay edits silently become baseline edits.

### 4. Rework Phrase Shell IA

Add the phrase-local shell:

- Perform toggle;
- dirty summary;
- Capture and Discard visible/disabled as appropriate;
- latch timing controls;
- tabs: Layers, Scenes, Global Apply.

Remove or demote any top-level Perform/Capture UI that conflicts with the new
phrase-local model.

### 5. Build Layers Surface

Use existing layer picker and matrix primitives where possible:

- eight-column track matrix;
- selected layer across tracks;
- direct cell click changes the value;
- Automation toolbar mode changes click behavior to open automation editing;
- no generic cell detail page.

Preserve current production visual language rather than copying the wireframe
labels verbatim.

### 6. Build Global Apply Surface

Implement scoped multi-track application:

- action choices in an eight-column matrix;
- scope count in the top bar;
- track-selector overlay in eight-column matrix form;
- Moment/Latch gate controls shared with layer performance;
- immediate application to the live phrase context.

This surface is like "cell value editing for a scope", not a separate
administration workflow.

### 7. Build Phrase Scenes Surface

Use the existing scene perform shape:

- slot A;
- crossfader;
- slot B;
- macro wells per scene slot.

Make it phrase-local, but do not build full continuous scene automation unless
the implementation needs a small data placeholder to avoid blocking later work.

### 8. Simplify Capture Phrase

Capture Phrase should open only a phrase-destination chooser:

- replace current phrase;
- save as a new phrase copy;
- choose another phrase slot.

Do not include Capture Clip, changed-cell review, quantize, or detailed
automation controls.

### 9. Visual And Interaction Evidence

Add or update visual scenarios so reviewers can see:

- transport current/next phrase;
- phrase shell Perform Off;
- phrase shell Perform On with dirty state;
- Layers;
- Global Apply with scope selector;
- Scenes;
- Capture Phrase destination chooser.

Where Peekaboo is unavailable, the build loop should record the blocker and
not declare visual completion.

### 10. Review Gates

Run and record:

- architecture review against `architecture.md`;
- spec review against `spec.md`;
- testing review against focused unit/integration coverage;
- UX/IA review against the V3 wireframe intent;
- visual-economy review against matrix grammar and anti-hybrid checklist.

The build is not done until all acceptance criteria in `spec.md` are either
implemented or explicitly deferred with product-owner approval.

## First Slice

The first implementation slice should be transport plus phrase shell state:

1. current/next phrase in transport;
2. phrase page shell with Perform toggle;
3. disabled Capture/Discard when Perform is off;
4. enabled live-copy state when Perform is on;
5. latch timing controls active only for Latch.

This creates the backbone that Layers, Scenes, Global Apply, and Capture can
attach to without inventing separate state.

## Non-Goals For This Build

- Performance groups.
- Capture Clip redesign.
- Cue output preview.
- Full continuous scene automation authoring.
- Track source/routing redesign.
- Drum kit group model changes unless required by scoped track selection.
- New business-form UI replacing matrix cells.
