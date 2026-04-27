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
- `.sample(sampleID:, settings:)` — plays a file from the read-only Application Support sample library; editor is `SamplerDestinationWidget` (see [[drum-track-mvp]])
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

`Project` now migrates those fields into `voicing.defaultDestination` during decode. New saves write only the `voicing` shape.

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
- a fixed-width macro slot row (M1–M8) for AU and sampler destinations
- an inline preset stepper (prev/next) beside the "Browse presets…" button

Important UI rule: the editor owns default destination state, while project routes are additive and live in the routing UI.

### AU destination card

The AU card renders:

- A current-preset pill showing the active preset name plus prev/next chevron buttons (`PresetStepper`). Rapid taps are guarded by an in-flight `Task` so only one load request runs at a time. A load failure surfaces an `exclamationmark.circle.fill` icon inline and colours the pill border red; the icon carries an accessibility label ("Preset failed to load").
- A fixed-width macro slot row of eight `AUMacroSlotKnob` views. Each slot shows its position label (M1–M8), a circular drag knob when bound, or a dashed ring with a `+` icon when empty. Tapping an empty slot opens `SingleMacroSlotPickerSheet`; right-clicking a bound slot shows a "Remove Macro" context menu item.

`AUMacroSlot` and `AUMacroSlotKnob` live in `Sources/UI/TrackDestination/AUMacroSlotKnob.swift`. The eight slots are always rendered; a slot's `binding: TrackMacroBinding?` is `nil` for unoccupied positions. Slot indices are stable: add or remove a binding and the surviving bindings do not shift positions.

`PresetStepper` (`Sources/UI/TrackDestination/PresetStepper.swift`) is a pure logic enum — it takes a `PresetReadout` and a `Direction` and returns the target `AUPresetDescriptor`. The view wires prev/next buttons in `TrackDestinationEditor` and disables them when no adjacent preset exists (single-preset list or no readout available).

`SingleMacroSlotPickerSheet` (`Sources/UI/TrackDestination/SingleMacroSlotPickerSheet.swift`) is a modal sheet that fetches the AU's parameter tree from `engineController.audioInstrumentHost(for:)?.parameterReadout()`, applies the same candidate-ranking logic as the existing multi-select `MacroPickerSheet`, and returns a single `AUParameterDescriptor`. Already-bound parameter addresses are excluded from the list. If the parameter tree is not available immediately, the sheet polls at 300 ms intervals for up to 6 seconds.

### Sampler destination card

`Sources/UI/SamplerDestinationWidget.swift` is restyled to match the AU card: a rounded panel with an eyebrow label, body content (gain slider, waveform, audition button), and an action row — so the two destination kinds look like siblings in the inspector.

Sampler tracks receive 8 built-in macros automatically on kind transition. The built-ins cover the full BuiltinMacroKind set: sample start, sample length, sample gain, and the five filter macros. See [[track-macros]] for the full slot model and kind-transition cascade.

## Testing and limits

The plan is covered by document, audio, platform, and controller tests. A few AU-host lifecycle cases are currently explicit test skips because `AVAudioUnitMIDIInstrument` destabilizes the macOS XCTest host during attach/detach under `xcodebuild`.

That means the main remaining confidence gap is manual smoke around:

- opening a real AU window
- editing parameters
- closing and reopening the document

The document shape, recent-voice store, and UI/editor plumbing are otherwise verified in the automated suite.

## Related pages

- [[track-macros]] — macro slot model, per-step clip lanes, and snapshot compiler precedence
- [[project-layout]] — where `Document/`, `Audio/`, `Platform/`, and `UI/` split responsibilities
- [[document-model]] — the wider `.seqai` persistence model
- [[routing]] — project-level additive routing on top of default destinations
