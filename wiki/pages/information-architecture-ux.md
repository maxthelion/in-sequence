---
title: "Information Architecture And UX"
category: "product"
tags: [ux, information-architecture, workspaces, tracks, phrases, mixer]
summary: The app's main workspaces, what each screen owns, and the UX boundaries that prevent duplicated or confusing controls.
last-modified-by: codex
---

## Purpose

This page describes where users should go to make each kind of decision.

The goal is not to freeze the UI. It is to keep feature work from duplicating controls across screens or hiding core state in the wrong place.

## Primary Workspaces

### Tracks

The Tracks workspace is the roster view.

It owns:

- creating tracks;
- creating drum/group bundles;
- showing grouped versus ungrouped tracks;
- selecting a track;
- giving compact status: type, destination, pattern slot, group membership, performance state.

It should not become the full editor for every track. It is the place to scan, select, and perform broad track-level gestures.

See [[tracks-matrix]] and [[track-groups]].

### Track Editor

The Track Editor owns detailed editing for one selected track or part.

It owns:

- source slot editing: clip, generator, empty source, source replacement;
- modifier chain placement and bypass;
- clip step editing;
- generator parameter editing;
- macro slot assignment and per-step macro lane editing;
- destination editing for the track;
- track-local preview controls such as fill preview.

The track editor should make the source/modifier model explicit. A user should be able to tell whether they are editing a clip, a generator, a modifier, or a destination.

### Phrase Matrix

The Phrase workspace is the full authoring matrix for project-scoped phrase layers.

It owns:

- phrase rows;
- track columns;
- layer selection;
- pattern-slot selection per track/phrase;
- phrase-level mute/fill/macro values;
- phrase length and repeat behavior as those features land.

The phrase matrix should show structure and authoring state. It should not duplicate every track's full source editor.

### Scene Perform

Scene Perform is the live performance surface for scene slots and crossfader state.

It owns:

- scene A / scene B selection;
- crossfader position;
- scene application/cue behavior;
- compact performance controls that relate to scene state.

Primary-clicking a populated scene matrix cell assigns that scene to its A or
B slot without moving the crossfader. Secondary-clicking performs a hard
switch as well: A lands at 0%, B at 100%.

It should not become the general mixer, and it should not hide phrase-arrangement controls that belong in the phrase workspace.

### Live / Track Perform

Live and performance-oriented track views are quick lenses over existing phrase/track state.

They own:

- toggles such as fill, note repeat, latch, and multi-select when those are performance gestures;
- immediate auditioning;
- grouped edits where the user wants one gesture to affect several tracks;
- saving performance changes back into the underlying phrase or pattern when explicitly requested.

They should disclose deeper editing progressively rather than placing every track editor control on the performance surface.

See [[live-view]].

### Mixer

The Mixer owns signal-level decisions.

It owns:

- per-track level, pan, mute/solo as implemented;
- routing to busses;
- send amounts;
- bus and send insert chains;
- master output inserts and metering;
- scene A/B mixer-state display where relevant.

Track cards may summarize destination/mix state, but the mixer is the place to make audio-level adjustments.

### Preferences

Preferences owns app/device setup.

It owns:

- MIDI interface selection and controller setup;
- audio interface selection;
- app support/library settings;
- permission-sensitive system integration.

Preferences should configure the environment. Project-specific musical routing belongs in the document workspaces.

## UX Rules

### One Primary Action Per Screen

Each screen should make its next likely action obvious. Secondary actions can exist, but they should not visually compete with the main flow.

### Progressive Disclosure

Keep high-frequency actions in the main surface and move lower-frequency branching decisions into local wells, popovers, or modals.

Examples:

- replacing a clip with a generator can be a quick remove/add-source flow;
- choosing from pools or creating less common source types can be disclosed after the source well is empty;
- modifier details can expand only when a modifier slot is selected.

### Group Related Controls By Flow

Controls that answer the same user question should sit together:

- source and modifier controls in the track editor;
- pattern/phrase controls in the phrase matrix;
- sends and bus routing in the mixer;
- controller mappings in preferences or a dedicated MIDI control surface view.

### Avoid Duplicate Truth

Screens can show summaries of state owned elsewhere, but there should be one canonical editing home for each decision.

For example:

- phrase cells choose pattern slots;
- track editor edits the selected source;
- mixer edits signal routing and effects;
- preferences edits hardware/device setup.

### Direct Manipulation And Hit Areas

The complete visible shape of a control is interactive. Pattern mini-cells,
step cells, track cards, menu rows, and icon buttons must not leave padding or
decorative subregions that only respond when the label or glyph is hit.

Step grids share one selection contract across melodic, chord, slicer, and
drum surfaces: primary click edits the step; secondary click selects or toggles
the whole step cell without changing its value. Selected steps expose the
shared Clear, Copy, and Paste action row. Paste stays disabled until both a
selection and clipboard content exist.

Phrase layer selection keeps the Layers/Scenes navigation visible. Choosing a
layer is a one-click, select-and-close operation; selection is carried by the
cell treatment rather than a separate check badge.

### Conditional Scroll Chrome

Contained editors use the shared themed scroll views. The track/thumb is hidden
when all content fits and appears only for genuine overflow. Converting a list
to custom scroll chrome must preserve ordering gestures, keyboard focus, and
accessibility order.

### Stub Off-Path Prototype Areas

Roadmap prototypes should keep off-path areas visibly stubbed. The prototype guidelines live in `docs/roadmap/prototype-guidelines.md` if present, and in `docs/working-through-a-roadmap.md`.

## Related Pages

- [[application-overview]]
- [[playback-data-path]]
- [[tracks-matrix]]
- [[live-view]]
- [[track-destinations]]
- [[routing]]
- [[track-groups]]
