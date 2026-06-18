---
feature: perform-mode-phrase-layer-capture
created: 2026-06-18
status: accepted PM architecture for builder handoff
sources:
  - README.md
  - docs/roadmap/perform-mode-phrase-layer-capture/reasoning-v3.md
  - docs/roadmap/perform-mode-phrase-layer-capture/prototypes/05-phrase-value-cell-system-v3.html
  - docs/roadmap/phrase-features/architecture.md
  - docs/roadmap/song-mode-phrase-looping/architecture.md
  - docs/roadmap/performance-layer-matrix/implementation-handoff.md
---

# Perform Mode, Phrase Layers, And Capture Architecture

## Scope

This architecture turns the V3 wireframe into a buildable model for the next
application version. The feature is not a pixel-for-pixel HTML port. It is a
set of phrase-first behavior, state, and IA changes that should be implemented
using existing app components wherever they fit.

The build should deliver:

- current/next phrase awareness in transport;
- phrase-local edit versus perform-copy semantics;
- phrase tabs for Layers, Scenes, and Global Apply;
- matrix-first layer performance across tracks;
- scoped global layer/value application;
- phrase-local scene performance using the current scene A/B grammar;
- capture phrase as a destination chooser for a modified phrase copy.

The build should not include:

- performance groups;
- cue-output preview;
- capture clip redesign;
- full continuous scene automation authoring;
- a second design system or business-workflow layout;
- a generic phrase-cell detail page.

## Architectural Delta

The existing app already has phrases, phrase cells, track cards, layer selection,
scene A/B perform UI, track perform mode, and capture/history concepts. This
feature changes where those concepts are coordinated.

The next version should make phrase the active performance context:

- transport shows the current phrase and optional next phrase;
- phrase pages edit the selected/current phrase;
- track and layer performance changes resolve through the phrase context;
- perform mode writes into a temporary phrase copy/overlay;
- capture chooses where that modified phrase is saved.

This is mostly a reorientation of existing surfaces around phrase state. It
should reuse current track cards, layer selector cells, scene slot/macro UI, and
matrix styling where possible.

## Data Model Decisions

### Phrase Baseline

The phrase baseline is canonical document state. It owns phrase-local values for
track layers such as pattern, mute, fill, repeat, and future layer values. When
Perform is off, edits go directly to this baseline through the existing document
mutation/undo path.

### Perform Copy

When Perform is on, edits go to a temporary live phrase copy or overlay. The
overlay must be separate from canonical phrase document state until capture.

The overlay must record enough information to answer:

- which phrase it is based on;
- which phrase cells changed;
- which layer values changed;
- whether changes are immediate, latched, per-bar, or automated;
- whether changed values came from direct cell edits, Global Apply, Scenes, or
  phrase-local performance gestures.

Implementation may use a copied phrase model or a sparse overlay map, but it
must preserve the user-visible semantics: Capture prints the modified phrase;
Discard returns to the baseline.

### Phrase Value Cell

A phrase value cell is the reusable unit for track/layer values. It is a tuple:

```text
phrase + target scope + layer + value + value mode + timing
```

Target scope can be a track, scene slot, macro, crossfader, or related phrase
entity. Value mode is one of:

- single value;
- per-bar;
- continuous/events;
- inherited/baseline;
- live overlay.

The production UI does not need to display these labels literally, but the data
path must be able to represent them.

### Current And Next Phrase

Transport/session state must distinguish:

- current phrase: the phrase currently resolving playback;
- next phrase: optional phrase queued for the next phrase boundary.

In Song mode, next phrase is proposed by the arrangement but can be overridden.
In Free mode, next phrase is empty until the user cues one.

### Moment And Latch

Moment is immediate. It should not consult quantize or length because that
defeats the purpose of momentary performance.

Latch can be quantized and optionally time-limited. The current wireframe shows
quantize and length in the phrase header because these are phrase-perform timing
rules, not capture rules.

The build should support the data path for:

- latch quantize target, initially next bar;
- optional latch length, initially one bar or held;
- applying latch timing to layer/global changes made while Latch is active.

## Engine Decisions

Playback should resolve effective phrase state in a single central path:

```text
document phrase baseline
  -> current phrase navigation state
  -> perform copy/overlay when Perform is on
  -> layer/global/scene effective values
  -> existing track/source/step evaluation
```

The engine must not let UI-only state create a separate playback truth. If the
track page says a phrase mutes a track, playback should also be muted. If
Perform is on and a layer value changes, the audible state should use the
overlay until capture or discard.

Moment/Latch should be sampled in the same live performance state used by the
existing perform controls. Avoid hot-path logging, heavy allocations, or
document mutation in audio/tick-adjacent code.

## UI Ownership

### Transport

Transport owns current phrase, next phrase, and phrase progress display. It
does not own Capture or Perform; those are phrase-local.

### Phrase Page

The phrase page owns:

- Perform On/Off;
- dirty/changed summary;
- Capture and Discard controls;
- phrase-local tabs: Layers, Scenes, Global Apply;
- latch timing controls.

Perform Off means baseline edit. Perform On means live copy/overlay edit.
Capture and Discard remain visible but disabled when Perform is off.

### Layers

Layers is the default phrase surface. It edits one selected layer across an
eight-column track matrix. A cell click changes the value for that layer by
default. Automation is an explicit toolbar mode that changes the click behavior
to open automation editing.

There should be no separate generic cell-detail page in this slice.

### Global Apply

Global Apply is phrase-local. It applies one layer/value action to every track
in the current scope, using the same matrix grammar as the layer picker. Scope
can be all tracks or the current track selection. Track selector should also use
eight-column cells so MIDI surfaces can map to it quickly.

### Scenes

Phrase Scenes should stay close to the existing scene perform UI for now:

- slot A;
- crossfader;
- slot B;
- scene macro wells.

The model should leave room for scene slot values, crossfader values, and macro
events to become phrase value cells later, but do not overbuild continuous scene
automation in the first slice.

### Capture Phrase

Capture Phrase is deliberately narrow. It asks where the modified phrase copy
should be saved in the phrase matrix.

It must not:

- review every changed cell;
- offer Capture Clip;
- own quantize;
- become a modal for unrelated capture workflows.

## Reuse Guidance

Prefer reusing:

- current track card layout;
- current layer picker/matrix cells;
- current scene A/B perform UI;
- existing phrase matrix styles and interaction patterns;
- existing phrase navigation state in `EngineController` if still current;
- current document mutation paths for baseline edits.

Avoid:

- duplicating track/source/mixer controls in new wrappers;
- making production screens look like forms or project-management boards;
- adding persistent state before the phrase/overlay boundary is clear;
- implementing HTML wireframe labels as production copy when icons or existing
  controls already communicate the state.

## Build Risk

The main risk is a hybrid implementation: old top-level perform/capture
controls plus new phrase-local controls, or new UI that appears phrase-aware
while playback still resolves through old track-only state.

The build loop must use `spec.md` as the pass/fail contract and treat the
anti-hybrid checklist as mandatory review input.
