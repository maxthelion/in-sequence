---
title: "Track Destinations"
category: "architecture"
tags: [audio, midi, destination, voicing, au, routing]
summary: The per-track destination model for sequencer-ai: Destination, Voicing, AU state persistence, recent-voice recall, and the destination editor workflow.
last-modified-by: codex
---

## Overview

Track output is now modeled as a per-track `Voicing`, not as a pair of loosely related `output` and `audioInstrument` fields.

The key ideas are:

- every track owns its own destination state
- destination state is serializable into the `.seqai` document
- AU state travels with the document as a `fullState` blob
- MIDI and AU outputs share one tagged union shape
- drum and slice defaults are expressed through the same model

This keeps routing and document persistence aligned: a track can have no default sink, a direct MIDI/AU sink, or later a more complex per-tag drum setup without inventing a second output model.

## Core types

### `Destination`

`Sources/Document/Destination.swift` defines the sink tagged union:

- `.midi(port, channel, noteOffset)`
- `.auInstrument(componentID, stateBlob)`
- `.internalSampler(bankID, preset)`
- `.none`

`Destination` is the concrete "where notes go" value. It is intentionally portable:

- MIDI endpoints are referenced by `MIDIEndpointName`
- AU instruments are referenced by `AudioComponentID`
- AU preset state is stored as opaque `Data`
- `.none` means the track relies on project routes instead of a default sink

### `Voicing`

`Sources/Document/Voicing.swift` wraps a `[VoiceTag: Destination]` map.

For melodic tracks, the important key is:

- `default`

For drum tracks, the same type supports per-tag destinations such as:

- `kick`
- `snare`
- `hat-closed`

This means the app does not need separate "melodic output" and "drum output" models. The drum UI can grow into per-tag editing later without changing persistence again.

## Defaults by track type

Track creation now seeds `Voicing.defaults(forType:)`:

- instrument tracks start at `.none`
- drum racks start with internal-sampler defaults for the seed kit tags
- slice tracks start with an internal-sampler slice placeholder

The important design point is that "playable immediately" and "editable later" are both represented in document data rather than hidden in controller defaults.

## Legacy migration

Older documents stored:

- `output`
- `audioInstrument`

`SeqAIDocumentModel` now migrates those fields into `voicing.defaultDestination` during decode. New saves write only the `voicing` shape.

That migration keeps older documents loadable while simplifying the live model the engine and UI see.

## AU state persistence

### `FullStateCoder`

`Sources/Audio/FullStateCoder.swift` is the archive bridge between AU `fullState` and document `Data`.

It uses `NSKeyedArchiver` / `NSKeyedUnarchiver` so the document can store AU state without knowing its internal schema.

### `AUAudioUnitFactory`

`Sources/Audio/AUAudioUnitFactory.swift` owns:

- instantiation of an AU from `AudioComponentID`
- restoring `fullState` into the unit
- capturing `fullState` back out of the unit

This keeps the serialization concern out of view code and out of the document model.

### `AUWindowHost`

`Sources/Audio/AUWindowHost.swift` opens a dedicated AppKit window for the selected track's AU UI and writes state back on close.

The flow is:

1. the engine creates or exposes the track's current `AVAudioUnit`
2. the destination editor asks `AUWindowHost` to open that unit
3. the host requests the plug-in's view controller
4. closing the window captures the unit's latest `fullState`
5. the track's `Destination.auInstrument(..., stateBlob:)` is updated in the document

That makes AU editing feel live while still making the document authoritative.

## Recent voices

`Sources/Platform/RecentVoicesStore.swift` stores cross-project voice recall at:

- `~/Library/Application Support/sequencer-ai/voices/history.json`

Each entry records:

- a friendly name
- the `Destination`
- first-seen / last-used timestamps
- optional project origin text

The destination editor uses this to surface a lightweight "voice history" without inventing a full preset-library format yet.

## Track destination editor

`Sources/UI/TrackDestinationEditor.swift` is the right-hand destination surface in the Track workspace.

It supports:

- selecting the default output kind
- editing MIDI endpoint/channel/transpose
- picking an AU instrument
- reopening the current AU plug-in window
- saving/recalling recent voices
- showing how many project routes currently fan out from the selected track

Important UI rule: the editor owns default destination state, while project routes are additive and live in the routing UI.

## Testing and limits

The plan is covered by document, audio, platform, and controller tests. A few AU-host lifecycle cases are currently explicit test skips because `AVAudioUnitMIDIInstrument` destabilizes the macOS XCTest host during attach/detach under `xcodebuild`.

That means the main remaining confidence gap is manual smoke around:

- opening a real AU window
- editing parameters
- closing and reopening the document

The document shape, recent-voice store, and UI/editor plumbing are otherwise verified in the automated suite.

## Related pages

- [[project-layout]] — where `Document/`, `Audio/`, `Platform/`, and `UI/` split responsibilities
- [[document-model]] — the wider `.seqai` persistence model
- [[routing]] — project-level additive routing on top of default destinations
