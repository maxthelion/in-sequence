---
title: "Slicer Tracks"
category: "architecture"
tags: [audio, sampler, slicer, track-destinations, playback]
summary: How slice tracks store SliceSet metadata, trigger slices from clips, and dispatch frame-range playback through the sample engine.
last-modified-by: codex
---

## Overview

Slice tracks use the same track/source/phrase machinery as other tracks, but their default destination is now a runtime slicer rather than a placeholder internal sampler.

The important split is:

- authored slice metadata lives in the document as a project-scoped `SliceSet`
- the track destination points at a slice set with track-wide `SlicerSettings`
- clip and generator sources emit voice tags such as `slice-3` or `slice-run-3`
- playback resolves those tags to frame ranges and asks `SamplePlaybackEngine` to play that slice immediately

That keeps slice layout reusable across tracks while preserving per-track gain, transpose, and mono/poly playback behavior.

## Document Model

`SliceSet` lives under `Sources/Document/` and is stored in `Project.sliceSetPool`.

Each set has:

- a stable `id`
- an optional `sampleID` pointing at an `AudioSample`
- ordered `SliceMarker` values
- analysis metadata: `mode`, optional `bpmHint`, optional `bars`

Marker index `0` is always the whole sample. `SliceSet.normalize(sampleLengthFrames:)` rewrites marker `0` to `[0, sampleLength]`, clamps marker ranges, sorts user slices, and removes invalid zero-length slices. The empty placeholder is `SliceSet.emptyID`, with no `sampleID`, so a newly created slice track can render "choose a loop" without a separate nil-destination branch.

`Destination.slicer(sliceSetID:settings:)` is the track destination. `SlicerSettings` owns track-wide gain, transpose, and voice mode; per-slice gain, reverse, micro-timing, and tag live on `SliceMarker`.

## Slice Sources

`ClipContent.sliceTriggers` stores:

- `stepPattern`
- `sliceIndexes`
- `stepModes`

`stepModes` is currently `.single` or `.runFromHere`. `.single` plays the selected marker range. `.runFromHere` starts at the selected marker and continues to marker `0`'s whole-sample end frame, which gives tracker-style "run from here" playback.

The generated-source evaluator converts slice trigger steps into generated notes with voice tags:

- `slice-N` for normal one-shot slice playback
- `slice-run-N` for run-from-here playback

The MIDI pitch is only a carrier value; the slicer runtime reads the voice tag.

## Engine Playback

`PlaybackSnapshot` carries `sliceSetPool` alongside tracks, clips, generators, and phrase buffers. `SnapshotChange.sliceSet(id)` lets marker edits update the snapshot without a full rebuild.

On each tick, `EngineController` resolves the normal phrase/pattern step, evaluates the source, and, for `.slicer` destinations:

1. reads the slice set from the snapshot
2. resolves the sample file from `AudioSampleLibrary`
3. maps each generated note's voice tag to a marker index
4. combines track gain with marker gain
5. enqueues `.sliceTrigger`
6. dispatches to `SamplePlaybackEngine.playSlice(...)`

`SamplePlaybackEngine` schedules frame ranges directly from `AVAudioFile`. Mono slicer mode reuses one voice per track; polyphonic mode uses the existing round-robin voice pool. Reversed slices use a small LRU cache keyed by `(fileURL, startFrame, endFrame)`.

## UI

`Sources/UI/Slicer/` contains the slicer destination UI.

`SlicerSourceWidget` appears in `TrackDestinationEditor` for `.slicer` destinations. It lets the user choose a sample, run grid or transient analysis, audition slices, adjust track-wide settings, and open the waveform editor.

`SlicerWaveformWindow` is a sheet-style waveform editor for marker-level edits. It displays the downsampled waveform, marker boundaries, a slice list, and a per-slice inspector for range, gain, timing, reverse, and tag.

## Related Pages

- [[track-destinations]] — the broader `Destination` model
- [[drum-track-mvp]] — sample library and sample playback foundations
- [[engine-architecture]] — playback snapshots and tick dispatch
- [[track-macros]] — built-in macro slots shared by sampler-like destinations
