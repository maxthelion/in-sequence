# V2 Reasoning

## What Changed

The previous prototype read too much like a workflow/control dashboard. This
version treats perform as a phrase-scoped instrument state:

- the transport has a current phrase button;
- song view is a phrase matrix, not a task list;
- phrase view owns layer, scene, and cell modes;
- tracks view is simple selection/opening, with selection used only as scope for
  phrase-layer changes;
- capture remains transport-level but intentionally light in this pass.

## Main IA

The hierarchy is:

- Song: matrix of phrases; open any phrase.
- Current phrase: opens the phrase editor for the named phrase.
- Phrase modes:
  - overview matrix;
  - phrase layers / layer perform;
  - phrase scenes;
  - selected phrase cell edit.
- Tracks: select tracks, open tracks, or add tracks.
- Mixer and Scenes: global setup/management stubs for this prototype.

## Perform Definition

The prototype takes a position on the open question:

Perform means editing a live copy of the current phrase while playback continues.
The live copy can be printed/captured into a phrase, or discarded.

This lets layer changes and scene crossfader moves share one mental model. It
also avoids making "perform" a separate business-style process flow.

## Phrase Values Over Time

Layer values inside a phrase should be understood as phrase-scoped values with a
time dimension, not only as static settings.

Default state:

- a phrase layer value has a single value for the whole phrase unless something
  more specific has been recorded;
- in phrase layers mode, the value and its bar/event map are two visible parts
  of one phrase cell, not separate rows or separate layers;
- the UI should therefore show the simple value first, and reveal per-bar or
  event detail only when the phrase actually contains it or the user chooses to
  edit at that level.

Perform state:

- perform mode is an alternate way of setting the same phrase-layer values while
  playback is running;
- a change made during perform mode has a position within the phrase cycle;
- if bar quantization is enabled, the affected bar or bars become part of the
  captured phrase data;
- without bar quantization, the captured data may need a finer event-like
  representation, but the UI can still summarize it as phrase-local automation.

Capture implication:

- capture phrase should print the temporary performance phrase, including the
  temporal placement of performed layer changes;
- capture should preserve whether a layer remains a single phrase-wide value,
  becomes per-bar values, or contains finer performance events;
- the visible phrase editor should make that distinction inspectable after
  capture, rather than flattening all performance changes into a single current
  value.

## Matrix Preference

Matrices are used as the main interaction surface:

- phrase slots in song view;
- track/layer cells in phrase overview;
- layer-per-track perform matrix, with each track represented as a phrase cell
  containing both the current layer value and its bar map;
- scene A/crossfader/B phrase cells, followed by macro-value cells for the
  selected scene slot;
- selected cell by bar;
- track selection grid.

Non-matrix controls only switch mode, set scope, or expose off-path stubs.

## Phrase Scenes

Phrase scenes need a more careful model than a simple A / crossfader / B table.

- the A slot and B slot each choose a scene, and that scene choice can be a
  single value, per-bar values, or finer continuous/event data;
- the crossfader is its own phrase value and can also be single, per-bar, or
  continuous/event data;
- macro knob values are recordable as events, but those values are tied to the
  scene currently loaded into the selected A or B slot;
- therefore the scene macro editor should be cell-based and scene-contextual:
  editing `A slot / Scene 02 / M1` is different from editing `B slot / Scene 07
  / M1`;
- if a slot changes scenes over the phrase, the UI needs to make clear which
  scene's macro values are being displayed or recorded at each point.

## Phrase Cell Edit

Cell edit is for inspecting and editing a tuple:

- selected phrase;
- selected track;
- selected layer;
- the layer value mode: single, per-bar, or event/continuous;
- the value map that says when the value applies.

It should not show unrelated phrase settings. Pattern length, track clip length,
scene A/B, and crossfader values belong to their own track or scene contexts.
The useful overview is a matrix of layer cells for the selected track; clicking a
layer cell opens the value/timing editor for that layer.

## Deliberately Deferred

Capture is placed but not fully solved. The prototype keeps a transport-level
Capture menu with Capture Phrase and Capture Clip options, but does not design
the full history/capture workflow again.

Performance groups are deliberately left out of this prototype. The concept
needs more thought before it becomes visible IA; track selection remains only as
a temporary scope for applying phrase-layer changes.

Cue-output preview is also deferred.
