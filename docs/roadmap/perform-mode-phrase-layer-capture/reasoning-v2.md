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
