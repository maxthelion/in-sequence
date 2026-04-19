---
title: "Live View"
category: "ui"
tags: [live, performance, phrases, layers, groups]
summary: The Live workspace for performance editing over phrase layer/cell state, including optional group fan-out.
last-modified-by: codex
---

## Overview

The `Live` workspace is the performance-facing editor for the current phrase/layer state.

It does not maintain a separate runtime-only structure. Instead, it edits the same phrase cells the Phrase workspace uses:

- project-scoped `layers`
- per-phrase, per-track `cells`

This means edits made in `Live` are immediately visible in `Phrase`, and vice versa.

## Editing target

`Live` always edits a real phrase:

- in `Free` transport mode, it edits the selected phrase
- in `Song` transport mode while running, it follows the currently playing phrase

That keeps live performance changes anchored to the same authored song/phrase model instead of drifting into a parallel overlay.

## Matrix model

The surface renders one lane per visible unit:

- one flat track per lane in expanded mode
- one aggregate `TrackGroup` lane in grouped mode

When grouped mode is enabled, edits fan out to all member tracks in that group lane.

If the member cells disagree, the lane shows a `Mixed` state. The next edit or mode change applies uniformly across the members.

## Type-driven editing

The selected layer determines both available edit modes and the editor UI:

- boolean layers use toggle-style editing
- pattern layers use pattern-slot picking
- scalar layers support `Single`, `Bars`, `Steps`, and `Curve`

This mirrors the same layer/value semantics used elsewhere in the app and keeps live editing aligned with the north-star `Layer` / `Cell` model.

## Why this exists

`Phrase` is the full authoring matrix.

`Live` is the quicker performance lens:

- fewer simultaneous dimensions on screen
- one selected lane editor at a time
- transport-aware phrase targeting
- optional group fan-out for drum kits and other grouped tracks

So it stays focused on performance edits instead of duplicating the whole Phrase matrix.

## Related pages

- [[track-groups]]
- [[tracks-matrix]]
- [[project-layout]]
