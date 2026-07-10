---
title: "Tracks Matrix"
category: "ui"
tags: [tracks, ui, groups, drums, creation]
summary: "The dedicated Tracks workspace: flat-track selection, grouped drum bundles, and the Add Drum Group creation modal."
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

The roster is presentation-filterable without changing document order or group
state. Its filter offers All, Mono, Poly, Chord, Slicer, Audio, Drum Kits, and
Drum Parts. Group members classify as Drum Parts before their underlying
melodic type is considered, so they do not leak into Mono or Poly results.

Drum Kits presents one card per group. Drum Parts presents the member cards
directly without expanding or mutating the group.

Cards stay small and identity-focused. The name is the primary label; track
type remains available to accessibility/help rather than as a logo and footer.
In selection mode, a selected track or kit uses its solid identity accent and a
dark foreground instead of a checkbox plus competing outline.

This keeps the matrix dense enough to scan without duplicating destination controls, generator settings, or full routing editors.

## Creation actions

The add card opens the shared creation flow for Mono, Poly, Chord, Slicer,
Audio, and Drum Group choices. A selected roster set exposes one Perform
command, which opens Phrase > Layers scoped to that set in By Track mode. It
also exposes Create Track Group, which saves the selection into one of sixteen
document-owned performance slots through a 4x4 picker.

`Add Drum Group` opens a modal that builds a `DrumGroupPlan`.

That flow supports blank or kit-backed groups and editable part names, tags,
and sounds. New groups route through their dedicated kit bus. Pattern templates
are applied after creation from the kit page.

Submitting the sheet calls `addDrumGroup(plan:)`, which appends the grouped bundle of mono tracks and creates the corresponding `TrackGroup`.

After creation, the new track (or first drum-kit member) becomes selected and the app routes into the single-track workspace.

## Performance track groups

`PerformanceTrackGroup` is deliberately separate from the routing-oriented
`TrackGroup` below. A performance group is a named, reusable ordered set of
track IDs used to scope Phrase Layers in either By Track or By Value mode.
The project owns a fixed bank of sixteen optional slots; legacy documents
decode with an empty bank, and deleting tracks prunes stale members and clears
groups that become empty.

Phrase exposes one scope menu: All Tracks, an optional Current Selection for a
direct Perform handoff, then occupied saved-group slots. It does not maintain a
second per-track checkbox sheet.

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
