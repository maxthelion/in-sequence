---
title: "Drum Track MVP"
category: "feature"
tags: [drums, tracks, samples, clips, destination, library, addDrumKit, ClipPoolEntry, TrackGroup]
summary: How drum-kit creation works end-to-end — per-member sample destinations, per-part owned clips, TrackGroup bundling, and the absent-generator default.
last-modified-by: wiki-maintainer
---

## Overview

A drum kit is a `TrackGroup` whose members are a set of normal mono-melodic tracks, one per drum preset part. The kit is created in one atomic call — `Project.addDrumKit(_:library:)` — which appends all member tracks, assigns per-member sample destinations, seeds per-part clips, and registers the group in a single mutation.

## What addDrumKit produces

For each member in the `DrumKitPreset`:

1. A `StepSequenceTrack` is created with the member's `trackName`, `trackType: .monoMelodic`, and a baseline drum note in its `pitches`.
2. The member's destination is picked by voice tag → category → first matching sample in `AudioSampleLibrary`. If no match is found, it falls back to `.internalSampler(bankID: .drumKitDefault, preset: preset.rawValue)`.
3. A `ClipPoolEntry` is created from the member's `seedPattern` — the clip carries the preset's suggested step sequence, typed as `.stepSequence(stepPattern:pitches:)`. This clip is appended to `Project.clipPool`.
4. A `TrackPatternBank` is built with `TrackPatternBank.default(for:initialClipID:)`, pointing all slots at that clip. `attachedGeneratorID` is `nil`.

All member tracks and their banks are appended together; then the `TrackGroup` is registered.

No generator is attached to any drum-kit track by default. If the user wants AI generation on a part, they add a generator to that specific track via the `GeneratorAttachmentControl` in the track editor — exactly the same flow as any other track type.

## Sample library

`AudioSampleLibrary.shared` is a process-global `@Observable` singleton that scans `~/Library/Application Support/sequencer-ai/samples/` at first access. The library is read-only for the user in this MVP — no import UI, no pool editing. Starter samples are shipped inside the `.app` bundle under `Resources/StarterSamples/` and copied to Application Support on first launch by `SampleLibraryBootstrap` (a manifest-hash-gated operation that also refreshes files on app upgrade).

Sample IDs are `UUIDv5(namespace: libraryNamespace, name: relativePath)` — deterministic across launches and machines — so documents reference samples by stable UUID even though the library itself is in-memory only.

## Destination

`Destination.sample(sampleID: UUID, settings: SamplerSettings)` is the destination variant for sample-backed tracks. `SamplerSettings` carries `gain` (UI-exposed), plus `transpose`, `attackMs`, `releaseMs` (reserved for the full sample-pool plan's UI).

## Playback

`SamplePlaybackEngine` lives on `EngineController`. It owns one `AVAudioEngine` with 16 main `AVAudioPlayerNode` voices (round-robin, steal-oldest) and a dedicated audition voice. `ScheduledEvent.Payload.sampleTrigger` is the queue payload; `EngineController.dispatchTick` drains and plays.

## Destination UI

`SamplerDestinationWidget` renders inline inside `TrackDestinationEditor` whenever the track's destination is `.sample`. Shows:
- Sample name + category + length.
- Waveform (64 mono abs-peak bars via `WaveformDownsampler` + a SwiftUI `Canvas`).
- Prev / audition / next controls (walks `library.samples(in: category)`).
- Gain slider (-60 to +12 dB, snaps to unity within 0.5 dB of zero).

## Clip ownership

Each drum-kit part gets its own `ClipPoolEntry`. Parts do not share clips. This means:

- editing one part's clip content does not affect siblings
- bypassing the generator on one slot (if one is later attached) falls back to that part's dedicated clip
- removing a kit from the track roster does not require pruning shared clip references — each clip is identifiable by its unique `UUID`

Pool pruning on kit removal is deliberately deferred; the pool may accumulate orphaned entries across a session.

## seedPattern

`DrumKitPreset.Member.seedPattern` is a `[Bool]` of 16 steps that pre-fills the part's clip. A typical kick uses `[true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false]`; hi-hat parts often have denser fills. The seed provides a musically sensible starting point without requiring user interaction before the part is audible.

## TrackGroup

The group carries shared metadata (name, color, optional `sharedDestination`, note mapping) that applies to all members. Members remain normal `StepSequenceTrack` entries in the flat `Project.tracks` array — the group is an overlay, not a nested container. See [[track-groups]] for the full group model.

## Overriding the default

To route all drum members through one AU instead of per-member samples: set each member's destination to `.inheritGroup`, then set the group's `sharedDestination` to the desired AU. The existing inheritance mechanism works unchanged.

## Backward compatibility

Documents written before this model was introduced have no clip entries in their pool for drum-kit tracks. `TrackPatternBank.synced` resolves slot clip IDs against the pool at load time; if no matching clip is found, the slot renders with `clipID = nil` and plays silence rather than crashing. The [[document-model]] versioning section covers the general decode strategy.

## Related

- [[document-model]] — TrackPatternBank, SourceRef, and the attachedGeneratorID field
- [[audio-sample-pool]] — the full project-scoped pool plan that extends this MVP
- [[track-groups]] — how TrackGroup bundles tracks without nesting
- [[track-destinations]] — where `.sample` fits alongside `.midi`, `.auInstrument`, …
- [[macro-coordinator]] — the mute filter that applies to sample dispatch too
