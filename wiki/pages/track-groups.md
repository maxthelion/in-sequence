---
title: "Track Groups"
category: "architecture"
tags: [tracks, groups, routing, drums, destinations]
summary: The flat track-group model, grouped drum bundles, and the create-time shared-destination flow.
last-modified-by: codex
---

## Overview

`TrackGroup` is the fresh-model replacement for the older per-tag voicing shape.

- every track still exists as a normal flat `StepSequenceTrack`
- a track may optionally belong to one `TrackGroup`
- a group may own a `sharedDestination`
- member tracks can point at `.inheritGroup` to resolve through that shared destination
- groups can also carry per-track `noteMapping` offsets when several members intentionally feed one shared output

This keeps the runtime simple: the engine still dispatches one track at a time, but grouped tracks can converge onto one AU or sampler host.

## Why this exists

The main use case is drum kits.

Instead of one special "drum rack" track with internal voice-tag routing, the document now stores one mono track per drum voice:

- Kick
- Snare
- Hat
- Clap

Those tracks are tied together by a `TrackGroup`:

- the group gives them a shared color and identity
- the group can carry one shared destination
- each member gets a note offset from `noteMapping`

That means drum voices are already flat tracks, so later views like Tracks matrix and Live view do not need special expansion logic just to expose them.

## Data shape

At the document level:

- `tracks: [StepSequenceTrack]`
- `trackGroups: [TrackGroup]`

Each track carries:

- `destination: Destination`
- `groupID: TrackGroupID?`

Each group carries:

- `id`
- `name`
- `color`
- `memberIDs`
- `sharedDestination`
- `noteMapping`
- `mute`
- `solo`

## Effective destination

At playback time the engine resolves a track like this:

1. if the track has its own concrete destination, use it directly
2. if the track uses `.inheritGroup`, look up its group
3. if the group has a `sharedDestination`, use that plus the member's `noteMapping` offset
4. otherwise fall back to `.none`

Grouped AU tracks therefore share one host when appropriate, while grouped MIDI tracks can still fan into one port/channel with different note offsets.

## Drum-kit flow

`DrumGroupPlan` is now the user-facing creation model for grouped drum tracks.

The Tracks workspace opens an `Add Drum Group` sheet that can:

- start from a blank four-row default or a `DrumKitPreset`
- optionally prepopulate clip step patterns
- optionally assign one shared destination to the group
- opt individual members into `.inheritGroup` while others keep per-voice defaults

`Project.addDrumGroup(plan:library:)` materialises that plan into flat member tracks, owned clips, pattern banks, and a `TrackGroup`.

`addDrumKit(_:)` still exists, but only as a compatibility shim that delegates to `addDrumGroup(plan:)` with a templated plan and no shared destination.

## Related pages

- [[track-destinations]]
- [[routing]]
- [[project-layout]]
