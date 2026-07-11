---
title: "Application Overview"
category: "product"
tags: [overview, product, tracks, phrases, clips, generators, mixer]
summary: A reader-facing overview of what the app does and how its main musical concepts fit together.
last-modified-by: codex
---

## What SequencerAI Is

SequencerAI is a macOS-native step sequencer for building and performing pattern-based music.

The app is organised around a few durable musical objects:

- **Tracks** are the playable lanes. A track may emit MIDI, host an AU instrument, play an internal sampler, or address another destination.
- **Pattern slots** are per-track source choices. Each track has a bank of slots; a slot can play a clip, a generator, or nothing.
- **Clips** are explicit step data: notes, velocities, chance, fill lane, and per-step macro overrides.
- **Generators** produce note data from musical rules: trigger stages, pitch stages, chord/progression logic, drum triggers, or slice triggers.
- **Phrases** choose what each track should do over time. Phrase layers can select pattern slots, mute tracks, enable fill, and set macro values.
- **Scenes** and performance modes sit above phrases and mixer state. They are for live transformations rather than low-level note entry.
- **Mixer state** controls track levels, busses, sends, master output, and effects as those features land.

The guiding idea is that a user can move between authored sequence data and generative behavior without losing either. A track can start as a clip, switch to a generator, preserve the clip as a fallback, and later capture generated output into explicit clip data.

## Core Workflow

The basic workflow is:

1. Create tracks or grouped track bundles.
2. Pick a destination for each track: MIDI, AU instrument, sampler, slicer, or shared group destination.
3. Choose whether each pattern slot plays a clip or a generator.
4. Edit clips directly in step views, or edit generator parameters.
5. Arrange behavior through phrase layers.
6. Perform by switching phrases, toggling fill, changing scenes, recording/capturing output, and adjusting mixer controls.

The app should feel like an instrument: direct enough for live decisions, but structured enough that those decisions can become saved musical state.

## Important Concept Boundaries

### Track Versus Source

A track is the lane and destination context. A source is what creates note data for a pattern slot.

This distinction matters because the same track can preserve both:

- a clip source for predictable step playback;
- a generator source for variation;
- modifiers or macro state that shape either source.

See [[document-model]] for `TrackPatternBank` and `SourceRef`.

### Clip Versus Generator

A clip is explicit data. A generator is a recipe. Both can produce notes for the same step, but they are authored and persisted differently.

Clips are best when the user wants predictability, editing, capture, and per-step detail. Generators are best when the user wants variation, rules, probability, or harmonic behavior.

See [[generator-algos]] and [[playback-data-path]].

### Phrase Versus Pattern Slot

A pattern slot says what a track can play. A phrase says which slot, mute state, fill state, and macro values should be active at each phrase step.

This lets one set of per-track pattern slots be reused across phrases without duplicating every clip or generator.

### Phrase Perform Palette

Phrase Perform includes a persistent 8x8 palette for reusable authored cells.
A Layer cell can be selected and copied into a palette slot; the stored entry
keeps snapshot track/layer labels for identification plus the typed performance
payload. Authored cells retain the complete `PhraseCell` value and automation
shape; Note Repeat cells retain their interval and on/off state. Pasting from
the palette into another Layer cell writes only that payload. It never changes
the target track or layer identity, and a Layer paste is enabled only when the
stored and target layer IDs match.

### Destination Versus Routing

A destination is the track's default sink. Routing is additive fan-out from one track's output to other destinations or contexts.

See [[track-destinations]] and [[routing]].

## Current Workspaces

The current app surfaces are described in [[information-architecture-ux]]. At a high level:

- **Tracks** is the roster and creation view.
- **Track Editor** edits the selected track's source, modifiers, clip/generator data, macros, and destination.
- **Phrase** arranges project-scoped layers across tracks and phrases.
- **Live / Perform** is the faster performance lens over phrase state.
- **Mixer** handles track/bus/master output controls.
- **Preferences** handles app-level setup such as MIDI and audio devices.

## Runtime Summary

Playback does not walk the full document model on every step. The app compiles document/live-store state into a `PlaybackSnapshot` made of typed buffers:

- `PhrasePlaybackBuffer` for per-step phrase values;
- `TrackSourceProgram` for each track's slot programs;
- `ClipBuffer` for compact clip-step data and macro overrides.

The tick path then resolves the current phrase step through those buffers, evaluates the selected clip or generator, converts generated notes into `NoteEvent`s, and dispatches them to audio/MIDI/routing sinks.

The full path is documented in [[playback-data-path]].

## Related Pages

- [[information-architecture-ux]]
- [[system-entity-diagrams]]
- [[playback-data-path]]
- [[document-model]]
- [[generator-algos]]
- [[track-destinations]]
- [[routing]]
- [[engine-architecture]]
