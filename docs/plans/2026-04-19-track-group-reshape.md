# Flat Tracks + TrackGroup Reshape Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the repo-wide move to the fresh flat-track model: tracks own inline destinations, groups own shared destinations and note offsets, drum kits are appended as grouped mono tracks, and phrases no longer carry a parallel macro-grid abstraction. This plan is the data-model and coherence foundation for `tracks-matrix` and `live-view`.

**Architecture:** The authoritative shape is now:

- `tracks: [StepSequenceTrack]` — flat ordered track list
- `track.destination: Destination`
- `track.groupID: TrackGroupID?`
- `trackGroups: [TrackGroup]`
- `layers: [PhraseLayerDefinition]` — project-scoped defaults and targets
- `phrases: [PhraseModel]` where each phrase carries `cells[(trackID, layerID)]`
- built-in `Pattern` / `Mute` / scalar layers instead of `trackPatternIndexes + macroGrid`

There is no `trackSlots`, no `Voicing`, no separate drum-rack track type, and no compatibility work required for the new shape.

**Tech Stack:** Swift 5.9+, Foundation, XCTest, SwiftUI.

**Parent spec:** `/Users/maxwilliams/dev/sequencer-ai/docs/specs/2026-04-18-north-star-design.md`

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Status:** Completed. The repo now uses the flat track + `TrackGroup` model, phrases are authored via project-scoped layers and per-cell values, and the downstream plans/spec speak that same model.

**Depends on:**

- `2026-04-19-track-destinations.md`
- `2026-04-19-midi-routing.md`

**Deliberately deferred:**

- Full disk-backed drum-kit library import/export
- Group bus FX chains and group-edit UI

---

## File Structure

```
Sources/
  Document/
    Destination.swift
    PhraseModel.swift
    SeqAIDocumentModel.swift
    TrackGroup.swift
  Engine/
    EngineController.swift
    MIDIRouter.swift
  UI/
    TracksMatrixView.swift
    PhraseWorkspaceView.swift
    DetailView.swift
Tests/
  SequencerAITests/
    Document/
      DestinationInheritGroupTests.swift
      SeqAIDocumentTests.swift
      TrackGroupTests.swift
    Engine/
      EngineControllerTests.swift
wiki/pages/
  track-groups.md
  project-layout.md
```

---

## Task 1: Fresh phrase/layer model only

**Scope:** Remove the last retired phrase abstractions from the active model and tests. The data model should speak only in terms of project-scoped layers and per-phrase cells.

**Files:**

- Modify: `Sources/Document/PhraseModel.swift`
- Modify: `Sources/Document/SeqAIDocumentModel.swift`
- Modify: `Tests/SequencerAITests/SeqAIDocumentTests.swift`

**Done when:**

1. `PhraseModel` exposes `cells[(trackID, layerID)]` as the only phrase-local control surface.
2. `PhraseLayerDefinition.defaultSet(for:)` creates the default built-in layers.
3. Pattern selection is derived from the `Pattern` layer, not a separate map.
4. Tests cover scalar / boolean / indexed cell behavior.

- [x] Implement fresh phrase/layer model
- [x] Replace legacy-heavy document tests with fresh-model coverage
- [x] Targeted `xcodebuild test` green

---

## Task 2: Flat tracks + group-aware destination resolution

**Scope:** Make the engine and document model treat `TrackGroup` as the shared routing authority when a track uses `.inheritGroup`.

**Files:**

- Modify: `Sources/Document/Destination.swift`
- Modify: `Sources/Document/SeqAIDocumentModel.swift`
- Modify: `Sources/Document/TrackGroup.swift`
- Modify: `Sources/Engine/EngineController.swift`
- Modify: `Tests/SequencerAITests/Engine/EngineControllerTests.swift`

**Done when:**

1. `Destination.inheritGroup` round-trips cleanly.
2. Grouped MIDI/AU members resolve through the group destination at tick time.
3. Shared AU destinations reuse one host per group.
4. Group note offsets are applied to inherited members.

- [x] Add `.inheritGroup`
- [x] Add `TrackGroup`
- [x] Resolve inherited destinations in `EngineController`
- [x] Cover shared-host and note-offset behavior in tests

---

## Task 3: Drum kit presets append grouped mono tracks

**Scope:** Replace the retired drum-rack track idea with a first-class drum-kit append flow.

**Files:**

- Modify: `Sources/Document/SeqAIDocumentModel.swift`
- Modify: `Tests/SequencerAITests/SeqAIDocumentTests.swift`

**Done when:**

1. `DrumKitPreset` exists with a small built-in library.
2. `addDrumKit(_:)` appends grouped mono tracks with `.inheritGroup`.
3. Group `noteMapping` is populated from the preset.
4. New tracks and new phrases sync into the same layer/cell world as melodic tracks.

- [x] Add preset library
- [x] Add grouped append flow
- [x] Cover note-mapping and phrase-sync behavior in tests

---

## Task 4: Spec and plan coherence

**Scope:** Update the north star and the downstream UI plans so they describe the fresh model instead of the retired `trackSlots` / `drumRack` / per-tag live expansion world.

**Files:**

- Modify: `docs/specs/2026-04-18-north-star-design.md`
- Modify: `docs/plans/2026-04-19-tracks-matrix.md`
- Modify: `docs/plans/2026-04-19-live-view.md`
- Modify: `wiki/pages/project-layout.md`
- Modify: `wiki/pages/track-groups.md`

**Done when:**

1. The north star describes `Layer` / `Cell` phrase structure consistently.
2. The tracks matrix plan is flat-track and group-aware.
3. The live view plan edits layer cells over the flat track list and treats groups as optional aggregates.
4. The wiki no longer describes the retired voicing/slot model as active.

- [x] Update spec
- [x] Update downstream plans
- [x] Update wiki where needed

---

## Task 5: Closure

**Scope:** Re-run the key slice, tick the plan, and tag the reshape once the repo and docs agree on the same world model.

**Verification command:**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project /Users/maxwilliams/dev/sequencer-ai/SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' \
  test
```

- [x] Full test suite green
- [x] Wiki updated
- [x] Plan marked completed
- [ ] Tag: `git tag -a v0.0.9-track-group-reshape -m "Flat tracks + TrackGroup reshape complete"`
