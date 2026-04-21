---
title: "Tracks Matrix"
category: "ui"
tags: [tracks, ui, groups, drums, creation]
summary: The dedicated Tracks workspace: flat-track selection, grouped drum bundles, and the Add Drum Group creation modal.
last-modified-by: codex
---

## Overview

The `Tracks` workspace is the app's entry point for browsing and creating tracks.

It reflects the fresh document model directly:

- the document owns a flat `tracks: [StepSequenceTrack]`
- related tracks may share a `TrackGroup`
- drum kits are grouped bundles of normal mono tracks

The matrix is intentionally not a second full track editor. It is for:

- scanning the current track roster quickly
- seeing which tracks belong together
- creating new tracks and drum groups
- selecting a track and jumping into the dedicated `Track` workspace

## Layout

The surface is split into sections:

- `Ungrouped` for standalone tracks
- one section per `TrackGroup`

Each group section can collapse to a compact member summary or expand to show its member cards inline.

Cards stay small and identity-focused:

- track name
- track type
- current pattern slot
- destination kind
- optional group badge / tint

This keeps the matrix dense enough to scan without duplicating destination controls, generator settings, or full routing editors.

## Creation actions

The top action row exposes the current type model directly:

- `Add Mono`
- `Add Poly`
- `Add Slice`
- `Add Drum Group`

The first three append one flat track each.

`Add Drum Group` opens a modal that builds a `DrumGroupPlan`.

That flow supports:

- blank starter groups
- preset-backed groups from `DrumKitPreset`
- optional clip prepopulation
- optional shared destination selection
- per-member `Routes to shared` control

Submitting the sheet calls `addDrumGroup(plan:)`, which appends the grouped bundle of mono tracks and creates the corresponding `TrackGroup`.

After creation, the new track (or first drum-kit member) becomes selected and the app routes into the single-track workspace.

## Group treatment

Track groups are visible in the matrix without reintroducing a fake hierarchical document model.

- grouped members are still normal tracks
- the section header carries the shared group identity
- the card tint/badge helps the user visually associate member tracks
- selecting a grouped member still opens that exact track

This is especially important for drums: the UI no longer needs a special "drum rack" track type just to make grouped drum voices legible.

## Related pages

- [[track-groups]]
- [[track-destinations]]
- [[project-layout]]
