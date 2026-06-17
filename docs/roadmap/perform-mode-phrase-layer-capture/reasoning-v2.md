# V2 Reasoning

## What Changed

The previous prototype read too much like a workflow/control dashboard. This
version treats perform as a phrase-scoped instrument state:

- the transport has a current phrase button;
- song view is a phrase matrix, not a task list;
- phrase view owns layer, scene, cell, and performance group modes;
- tracks view is simple selection/opening, with group creation as the main
  action;
- capture remains transport-level but intentionally light in this pass.

## Main IA

The hierarchy is:

- Song: matrix of phrases; open any phrase.
- Current phrase: opens the phrase editor for the named phrase.
- Phrase modes:
  - overview matrix;
  - phrase layers / layer perform;
  - phrase scenes;
  - selected phrase cell edit;
  - performance groups.
- Tracks: select tracks, open tracks, add tracks, or make a performance group.
- Mixer and Scenes: global setup/management stubs for this prototype.

## Perform Definition

The prototype takes a position on the open question:

Perform means editing a live copy of the current phrase while playback continues.
The live copy can be printed/captured into a phrase, or discarded.

This lets layer changes, scene crossfader moves, and grouped track changes share
one mental model. It also avoids making "perform" a separate business-style
process flow.

## Phrase Values Over Time

Layer values inside a phrase should be understood as phrase-scoped values with a
time dimension, not only as static settings.

Default state:

- a phrase layer value has a single value for the whole phrase unless something
  more specific has been recorded;
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
- layer-per-track perform matrix;
- scene A/crossfader/B by phrase/bar;
- selected cell by bar;
- performance group matrix;
- track selection grid.

Non-matrix controls only switch mode, set scope, or expose off-path stubs.

## Deliberately Deferred

Capture is placed but not fully solved. The prototype keeps a transport-level
Capture menu with Capture Phrase and Capture Clip options, but does not design
the full history/capture workflow again.

Cue-output preview is also deferred.
