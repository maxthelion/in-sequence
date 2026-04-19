---
title: "Routing"
category: "architecture"
tags: [midi, routing, fanout, chord, tracks, matrix]
summary: The project-level MIDI routing layer in sequencer-ai: Route values, MIDIRouter fan-out, chord-context lanes, and the inspector routes UI.
last-modified-by: codex
---

## Overview

Routing is now a project-level layer that sits between track note generation and concrete destinations.

A track can:

- play only to its own default `Voicing`
- play only through project routes
- play to both its own default sink and one or more additional route destinations

That additive behavior is the important architectural choice. Routes are not a replacement for `Voicing`; they are a fan-out layer on top of it.

## `Route` model

`Sources/Document/Route.swift` defines the persisted route shape:

- `source`
- `filter`
- `destination`
- `enabled`

### Sources

- `.track(trackID)`
- `.chordGenerator(trackID)`

### Filters

- `.all`
- `.voiceTag(tag)`
- `.noteRange(lo, hi)`

### Destinations

- `.voicing(trackID)`
- `.trackInput(trackID, tag)`
- `.midi(port, channel, noteOffset)`
- `.chordContext(broadcastTag)`

This is the minimum useful set for the current engine:

- duplicate a track to another sink
- forward note events into another track's input
- publish chord context
- split by tag or note range

## Document ownership

Routes live on the document, not on individual tracks:

- `SeqAIDocumentModel.routes: [Route]`

That makes them project-scoped wiring rather than per-track view state. The document also exposes helpers for:

- routes sourced from a given track
- routes targeting a given track

The selected track UI uses those helpers to show local route summaries without owning the routing model itself.

## `MIDIRouter`

`Sources/Engine/MIDIRouter.swift` is the runtime fan-out layer.

At tick time:

1. `EngineController` collects each track's note output for the current tick
2. the controller hands those `RouterTickInput` values to `MIDIRouter`
3. the router matches sources, filters, and enabled routes
4. the router emits `RouterEvent.note` or `RouterEvent.chord`
5. `EngineController` flushes those routed events to concrete destinations

The route snapshot is immutable during a tick and replaced atomically between ticks, so UI edits do not mutate the live route list mid-dispatch.

## Concrete delivery

`EngineController` remains the owner of actual sink delivery:

- direct track output still goes to the track's own default `Voicing`
- routed notes are flushed afterward
- routed MIDI destinations use per-destination `MidiOut` blocks
- routed `.voicing(...)` and `.trackInput(...)` resolve through the target track's `Voicing`
- routed `.chordContext(...)` updates the controller's chord-context lane map

This split keeps `MIDIRouter` simple: it decides what should fan out, while `EngineController` decides how each destination is executed.

## `ChordContextSink`

`Sources/Engine/Blocks/ChordContextSink.swift` is the pipeline bridge from block output to the router's chord lane machinery.

It consumes a chord stream and publishes the current chord to the routing layer, which allows chord-generator-style sources to drive downstream consumers through routes instead of hard-coded wiring.

## UI surfaces

Two views provide the current MVP routing UI:

- `RoutesListView`
- `RouteEditorSheet`

They currently live in the inspector/track-destination surface rather than a dedicated matrix view.

The UI supports:

- adding a default route from the selected track
- editing source/filter/destination
- deleting routes
- seeing a per-track "Routes Out" count

This is intentionally compact. A fuller AUM-style routing matrix is still a later UI plan.

## Relationship to phrase and track views

Today, the selected track surface is where you author routes. The future direction is:

- track view for destination defaults and local route awareness
- phrase/song surfaces for higher-level pattern and macro authoring
- a dedicated routing matrix when the UI plan for that lands

So the current routing UI is correct functionally, but not yet the final interaction design.

## Testing and limits

The routing layer is covered by:

- `RouteTests`
- `MIDIRouterTests`
- `ChordContextSinkTests`
- `TrackFanOutTests`

Current limits:

- no dedicated routing matrix UI yet
- no internal-sampler runtime sink yet
- no richer predicates beyond voice-tag and note-range
- no sample-accurate sub-tick scheduling

## Related pages

- [[track-destinations]] — the default sink model that routes fan out into
- [[engine-architecture]] — the executor/controller runtime that owns tick dispatch
- [[midi-layer]] — CoreMIDI transport underneath routed MIDI destinations
