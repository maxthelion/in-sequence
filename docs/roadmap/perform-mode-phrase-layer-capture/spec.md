---
feature: perform-mode-phrase-layer-capture
created: 2026-06-18
status: accepted builder-facing behavior spec
sources:
  - README.md
  - docs/roadmap/perform-mode-phrase-layer-capture/architecture.md
  - docs/roadmap/perform-mode-phrase-layer-capture/reasoning-v3.md
  - docs/roadmap/perform-mode-phrase-layer-capture/prototypes/05-phrase-value-cell-system-v3.html
---

# Perform Mode, Phrase Layers, And Capture Spec

## Product Contract

The next application version should make phrase the primary performance context.
A user can see the current and next phrase, edit a phrase baseline, enter
Perform to modify a temporary phrase copy while playback continues, and capture
that modified phrase to a phrase matrix destination.

The implementation must preserve the app's matrix-based groovebox character.
It should reuse existing controls and layouts where they already express the
right concept.

## Functional Delta Checklist

### Transport

- Shows the current phrase.
- Shows an optional next phrase.
- In Song mode, next phrase is supplied by arrangement order.
- In Free mode, next phrase is empty until the user cues one.
- User can override the next phrase before the boundary.
- Shows progress toward the next phrase boundary.
- Does not expose top-level Capture or Perform as global app modes.

### Top-Level Navigation

- Song is a top-level workspace for choosing, cueing, and arranging phrases.
- The current phrase is a separate top-level workspace item, labelled with the
  selected phrase name where practical.
- Opening a phrase from Song switches into that selected phrase workspace.
- Song must not be collapsed into a generic `Phrase` workspace.
- The current phrase workspace must not contain the all-phrases arrangement
  matrix.

### Phrase Shell

- Selecting/opening a phrase shows phrase-local controls.
- Phrase-local tabs are Layers, Scenes, and Global Apply.
- Perform Off means edits mutate the phrase baseline through normal document
  edit paths.
- Perform On means edits mutate a temporary live phrase copy/overlay.
- Dirty/changed summary is visible when Perform is on.
- Capture and Discard are visible but disabled when Perform is off.
- Capture and Discard are enabled when Perform is on and a live copy exists.
- Latch timing controls live in the phrase header/bar.
- Moment mode disables or visually de-emphasizes quantize/length because moment
  is immediate.
- Latch mode enables quantize and length.

### Layers

- Layers is the default phrase tab.
- The surface uses an eight-column track matrix.
- One selected layer is mapped across tracks.
- Cell click changes the selected layer value by default.
- Automation is a toolbar mode; when armed, clicking a cell opens automation
  editing for that track/layer.
- The old generic Cell Detail page is not present.
- The old "apply same value" button is not present on Layers.
- Current track selection/scope is visible where multi-cell editing depends on
  it.

### Global Apply

- Global Apply is phrase-local, not top-level.
- It applies one layer/value action to every track in the current scope.
- The action choices are matrix cells, not a form.
- The scope summary shows the number of tracks affected.
- Track selector uses an eight-column matrix.
- Moment and Latch controls are available here because the same gesture model
  applies to scoped changes.
- Global Apply does not duplicate a lower detail panel.

### Scenes

- Scenes remains visually and conceptually close to the current scene perform
  surface.
- It shows slot A, crossfader, and slot B.
- Scene macro wells remain associated with the scene in their slot.
- Phrase-local scene values can be edited against the current phrase context.
- Continuous scene/macro event authoring is not required in the first slice,
  but the model must not block it.

### Capture Phrase

- Capture opens a small destination chooser.
- The only decision is where in the phrase matrix the modified phrase is saved.
- The user can replace the current phrase, save as a new phrase copy, or choose
  another phrase slot.
- Capture does not show a changed-cell review panel.
- Capture does not offer Capture Clip.
- Capture does not own quantize or latch length.

### Tracks

- Tracks remains a top-level page for opening and managing tracks.
- Track selection can scope phrase-local Global Apply.
- Track cards should keep their current production visual language.
- Track-level source/routing/mixer work is not part of this build unless needed
  to keep phrase values honest.

## Data And Engine Checklist

- Phrase baseline values remain canonical document state.
- Perform copy/overlay is separate from document state until capture.
- Discard removes the live copy/overlay and restores baseline playback.
- Capture writes the modified phrase to the chosen destination.
- Effective playback resolves through current phrase state.
- Effective playback includes perform overlay values while Perform is on.
- Moment changes are immediate and do not consult quantize/length.
- Latch changes can quantize to the next bar and optionally expire after a
  configured length.
- Phrase current/next state is central enough that transport, phrase pages, and
  playback agree.
- Baseline edits participate in undo/dirty state according to current document
  conventions.
- Perform overlay edits do not silently dirty the document before capture unless
  the existing app intentionally represents live overlays as dirty state.
- Capture is the moment where live phrase-copy changes become document changes.

## Anti-Hybrid Checklist

Reviewers should fail the build if any of these are true:

- The app shows both old global Perform/Capture controls and new phrase-local
  Perform/Capture controls.
- The top-level navigation collapses Song and the selected phrase into one
  generic Phrase page.
- The selected phrase workspace still renders all phrase rows instead of only
  the selected phrase's layer values.
- Capture Phrase still contains Capture Clip.
- Capture Phrase still reviews individual changed cells instead of only asking
  for a phrase destination.
- Quantize is inside Capture instead of phrase/latch timing.
- Moment gestures are delayed by quantize.
- Layers still opens a generic Cell Detail page for normal value changes.
- Layer/global controls are laid out like a business workflow form rather than
  an eight-column matrix.
- UI indicates a phrase value changed but playback ignores it.
- Playback uses a different current phrase from the one shown in transport.
- The implementation creates a second unrelated layer picker instead of reusing
  or extending the current matrix grammar.

## Acceptance Criteria

1. Current phrase, next phrase, and progress are visible in transport.
2. Song mode proposes next phrase and Free mode starts with no next phrase.
3. The user can cue/override the next phrase.
4. Phrase page has Layers, Scenes, and Global Apply tabs.
5. Perform Off edits phrase baseline directly.
6. Perform On edits a live phrase copy/overlay.
7. Capture/Discard are visible but disabled when Perform is off.
8. Dirty/changed state is visible when Perform is on and changes exist.
9. Latch timing controls are phrase-local and inactive in Moment mode.
10. Layers uses an eight-column matrix and direct cell click changes values.
11. Automation mode changes layer-cell click behavior to open automation editing.
12. Global Apply applies a chosen layer/value to the current track scope.
13. Global Apply track scope selection uses an eight-column matrix.
14. Scenes keeps the current scene A/B/crossfader shape.
15. Capture Phrase only chooses a phrase destination.
16. Capture writes the perform copy to the chosen phrase destination.
17. Discard removes the perform copy without saving it.
18. Playback and UI agree about phrase mute/fill/pattern/repeat values.
19. Moment changes are immediate.
20. Latch changes can be quantized to next bar and length-limited.
21. No deferred performance-group UI is implemented.
22. No Capture Clip redesign is implemented.
23. No generic Cell Detail page remains in this flow.
24. Visual review evidence shows the built surfaces compared with the V3
    wireframe intent.

## Verification Scenarios

Use the smallest possible automated checks plus visual evidence:

- Start in Free mode: current phrase visible, next phrase empty.
- Cue Phrase B: next phrase updates and progress remains visible.
- Switch Song mode: next phrase is proposed by arrangement.
- Open Phrase A: Layers is the default tab.
- Perform Off: Capture and Discard disabled.
- Turn Perform On: change one layer cell, dirty summary updates.
- Moment selected: quantize/length inactive; change applies immediately.
- Latch selected: quantize/length active; change lands on next bar.
- Open Global Apply: choose Fill or Mute for selected tracks, verify only scoped
  tracks change.
- Open Scenes: A/B/crossfader layout matches current scene perform direction.
- Capture: only destination choices are shown; save to new phrase copy.
- Discard: live copy is removed and baseline returns.
