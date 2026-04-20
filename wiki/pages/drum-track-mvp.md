---
title: "Drum Track MVP"
category: "feature"
tags: [drums, samples, destination, library, application-support]
summary: How drum-kit tracks get audible output via per-member sample destinations backed by a read-only Application Support library.
last-modified-by: codex
---

## What this is

When the user calls `Add Drum Kit (808 / Acoustic / Techno)` in the UI, each member track of the preset receives a `Destination.sample(sampleID:, settings:)` pointing at a category-matched starter sample from the app's sample library. Tracks get audio output end-to-end without importing their own sounds.

## Sample library

`AudioSampleLibrary.shared` is a process-global `@Observable` singleton that scans `~/Library/Application Support/sequencer-ai/samples/` at first access. The library is read-only for the user in this MVP — no import UI, no pool editing. Starter samples are shipped inside the `.app` bundle under `Resources/StarterSamples/` and copied to Application Support on first launch by `SampleLibraryBootstrap` (a manifest-hash-gated operation that also refreshes files on app upgrade).

Sample IDs are `UUIDv5(namespace: libraryNamespace, name: relativePath)` — deterministic across launches and machines — so documents reference samples by stable UUID even though the library itself is in-memory only.

## Destination

`Destination.sample(sampleID: UUID, settings: SamplerSettings)` is the destination variant for sample-backed tracks. `SamplerSettings` carries `gain` (UI-exposed), plus `transpose`, `attackMs`, `releaseMs` (reserved for the full sample-pool plan's UI).

## Playback

`SamplePlaybackEngine` lives on `EngineController`. It owns one `AVAudioEngine` with 16 main `AVAudioPlayerNode` voices (round-robin, steal-oldest) and a dedicated audition voice. `ScheduledEvent.Payload.sampleTrigger` is the queue payload; `EngineController.dispatchTick` drains and plays.

## UI

`SamplerDestinationWidget` renders inline inside `TrackDestinationEditor` whenever the track's destination is `.sample`. Shows:
- Sample name + category + length.
- Waveform (64 mono abs-peak bars via `WaveformDownsampler` + a SwiftUI `Canvas`).
- Prev / audition / next controls (walks `library.samples(in: category)`).
- Gain slider (-60 to +12 dB, snaps to unity within 0.5 dB of zero).

## Overriding the default

To route all drum members through one AU instead of per-member samples: set each member's destination to `.inheritGroup`, then set the group's `sharedDestination` to the desired AU. The existing inheritance mechanism works unchanged.

## Related

- [[audio-sample-pool]] — the full project-scoped pool plan that extends this MVP
- [[track-destinations]] — where `.sample` fits alongside `.midi`, `.auInstrument`, …
- [[macro-coordinator]] — the mute filter that applies to sample dispatch too
