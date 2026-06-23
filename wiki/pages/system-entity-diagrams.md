---
title: "System Entity Diagrams"
category: "architecture"
tags: [uml, entities, document-model, runtime, diagrams]
summary: "Diagram guide for sequencer-ai entities: persisted document objects, source and phrase resolution, and the runtime playback snapshot path."
last-modified-by: codex
---

## What Kind Of Diagram Fits?

Different diagrams answer different questions:

- **UML class diagram:** best for "what entities exist, what do they own, and what do they reference?" This is the right default for the document model.
- **ER-style diagram:** best for persisted pools and references, especially `UUID` relationships such as tracks, clips, generators, phrases, routes, and groups.
- **Runtime data-flow diagram:** best for "how does authored state become note events?" This is more useful than UML for the engine hot path.
- **Sequence diagram:** best for one scenario, such as "user toggles fill" or "tick prepares notes for a track."
- **State machine:** best for modes like source slot empty/clip/generator, transport free/song mode, record armed/recording/auditioning/saved, or scene A/B crossfader modes.
- **UX flow / activity diagram:** best for workflows where the pain is interaction sequencing rather than data shape.

For this app, the useful set is: one class/ER hybrid for persisted entities,
one runtime ownership map, one data-flow diagram for playback, one focused
audio graph/routing map, and smaller state machines for specific roadmap
features.

Canonical architecture diagrams now live as D2 source under
`docs/diagrams/src/`, with rendered SVG artifacts under `docs/diagrams/`.
Inline Mermaid remains useful for quick local explanations, but the checked-in
D2 files are the source of truth for system ownership boundaries.

## Canonical D2 Maps

- Persisted entity model:
  `docs/diagrams/src/system-entity-model.d2` renders to
  `docs/diagrams/system-entity-model.svg`.
- Runtime ownership map:
  `docs/diagrams/src/runtime-ownership-map.d2` renders to
  `docs/diagrams/runtime-ownership-map.svg`.
- Playback snapshot path:
  `docs/diagrams/src/playback-snapshot-path.d2` renders to
  `docs/diagrams/playback-snapshot-path.svg`.
- Audio graph routing map:
  `docs/diagrams/src/audio-graph-routing-map.d2` renders to
  `docs/diagrams/audio-graph-routing-map.svg`.

The shared ownership vocabulary lives in
`docs/architecture/runtime-ownership-manifest.yml`. Run
`scripts/diagrams/check-d2-rendered.sh` to verify SVGs match the D2 sources and
`scripts/diagnostics/runtime-ownership-lint.sh` for the first mechanical
runtime-boundary checks.

## Persisted Entity Model

Source: `docs/diagrams/src/system-entity-model.d2`.
Rendered SVG artifact: `docs/diagrams/system-entity-model.svg`.

This diagram is a UML-ish view of the main document entities. Solid diamonds mean "owned in the `.seqai` project." Dashed arrows mean "referenced by ID."

```mermaid
classDiagram
direction LR

class SeqAIDocument {
  +Project model
}

class Project {
  +Int version
  +UUID selectedTrackID
  +UUID selectedPhraseID
  +tracks[]
  +trackGroups[]
  +patternBanks[]
  +clipPool[]
  +generatorPool[]
  +sliceSetPool[]
  +layers[]
  +phrases[]
  +routes[]
  +masterBus
}

class StepSequenceTrack {
  +UUID id
  +String name
  +TrackType trackType
  +Destination destination
  +TrackGroupID? groupID
  +TrackMixSettings mix
  +TrackMacroBinding[] macros
}

class TrackGroup {
  +UUID id
  +String name
  +UUID[] memberIDs
  +Destination? sharedDestination
  +noteMapping[trackID]
}

class TrackPatternBank {
  +UUID trackID
  +TrackPatternSlot[16] slots
  +UUID? attachedGeneratorID
}

class TrackPatternSlot {
  +Int slotIndex
  +SourceRef sourceRef
}

class SourceRef {
  +TrackSourceMode mode
  +UUID? generatorID
  +UUID? clipID
  +UUID? modifierGeneratorID
  +Bool modifierBypassed
}

class ClipPoolEntry {
  +UUID id
  +String name
  +TrackType trackType
  +ClipContent content
  +MacroLane[] macroLanes
}

class ClipContent {
  <<enum>>
  noteGrid
  sliceTriggers
}

class GeneratorPoolEntry {
  +UUID id
  +String name
  +TrackType trackType
  +GeneratorKind kind
  +GeneratorParams params
}

class SliceSet {
  +UUID id
  +markers[]
}

class PhraseLayerDefinition {
  +String id
  +String name
  +PhraseLayerTarget target
  +defaults[trackID]
}

class PhraseModel {
  +UUID id
  +String name
  +Int lengthBars
  +Int stepsPerBar
  +PhraseCellAssignment[] cells
}

class PhraseCellAssignment {
  +UUID trackID
  +String layerID
  +PhraseCell cell
}

class PhraseCell {
  <<enum>>
  inheritDefault
  single
  bars
  steps
  curve
}

class Route {
  +UUID id
  +RouteSource source
  +RouteFilter filter
  +RouteDestination destination
  +Bool enabled
}

class MasterBusState {
  +MasterBusScene[] scenes
  +UUID activeSceneID
  +MasterBusABSelection abSelection
}

class Destination {
  <<enum>>
  midi
  auInstrument
  internalSampler
  sample
  slicer
  inheritGroup
  none
}

SeqAIDocument *-- Project
Project *-- StepSequenceTrack : tracks
Project *-- TrackGroup : trackGroups
Project *-- TrackPatternBank : patternBanks
Project *-- ClipPoolEntry : clipPool
Project *-- GeneratorPoolEntry : generatorPool
Project *-- SliceSet : sliceSetPool
Project *-- PhraseLayerDefinition : layers
Project *-- PhraseModel : phrases
Project *-- Route : routes
Project *-- MasterBusState : masterBus

StepSequenceTrack *-- Destination : destination
TrackGroup *-- Destination : sharedDestination
TrackGroup ..> StepSequenceTrack : memberIDs
StepSequenceTrack ..> TrackGroup : groupID

TrackPatternBank *-- TrackPatternSlot : slots
TrackPatternSlot *-- SourceRef : sourceRef
TrackPatternBank ..> StepSequenceTrack : trackID
TrackPatternBank ..> GeneratorPoolEntry : attachedGeneratorID
SourceRef ..> GeneratorPoolEntry : generatorID
SourceRef ..> ClipPoolEntry : clipID
SourceRef ..> GeneratorPoolEntry : modifierGeneratorID

ClipPoolEntry *-- ClipContent
ClipContent ..> SliceSet : sliceSetID when slice-backed
PhraseModel *-- PhraseCellAssignment : cells
PhraseCellAssignment *-- PhraseCell
PhraseCellAssignment ..> StepSequenceTrack : trackID
PhraseCellAssignment ..> PhraseLayerDefinition : layerID

Route ..> StepSequenceTrack : track source or target
Route ..> Destination : MIDI / voicing / chord context
```

## Source And Phrase Resolution

This diagram shows why the model is split between pattern slots and phrases. A track owns the lane and destination. A pattern slot chooses the source. A phrase chooses which slot and layer values are active over time.

```mermaid
flowchart LR
  Track["StepSequenceTrack\nlane + destination context"]
  Bank["TrackPatternBank\n16 pattern slots per track"]
  Slot["TrackPatternSlot\nslotIndex + SourceRef"]
  SourceRef["SourceRef\nmode + clipID + generatorID + modifier"]
  Clip["ClipPoolEntry\nexplicit step data"]
  Generator["GeneratorPoolEntry\nrule-based source"]
  Modifier["GeneratorPoolEntry\nmodifier stage"]
  Phrase["PhraseModel\nlength + cells"]
  Layer["PhraseLayerDefinition\npattern, mute, fill, macros"]
  Cell["PhraseCellAssignment\ntrackID + layerID + value"]
  Destination["Destination\nMIDI, AU, sampler, slicer, group"]

  Track --> Bank
  Bank --> Slot
  Slot --> SourceRef
  SourceRef -->|mode = clip| Clip
  SourceRef -->|mode = generator| Generator
  SourceRef -->|optional| Modifier
  Track --> Destination

  Phrase --> Cell
  Layer --> Cell
  Cell -->|selects pattern slot| Bank
  Cell -->|sets mute/fill/macros| Track
```

Key invariants:

- A pattern slot can preserve both clip and generator IDs; `SourceRef.mode` decides which one currently plays.
- Phrase state selects pattern slots and performance layers. It does not copy clips or generators.
- Modifier generators process source notes without forking the final note-event path.

## Runtime Snapshot Path

Source: `docs/diagrams/src/playback-snapshot-path.d2`.
Rendered SVG artifact: `docs/diagrams/playback-snapshot-path.svg`.

This diagram is more appropriate than a class diagram for the engine. The important architecture rule is that the tick path reads compiled buffers, not arbitrary SwiftUI or document state.

```mermaid
flowchart TD
  Project["Project / LiveSequencerStoreState"]
  Compiler["SequencerSnapshotCompiler"]
  Snapshot["PlaybackSnapshot"]
  PhraseBuffer["PhrasePlaybackBuffer\nper-phrase step arrays"]
  SourceProgram["TrackSourceProgram\nslot programs per track"]
  ClipBuffer["ClipBuffer\ncompact clip steps + macro overrides"]
  Engine["EngineController.prepareTick"]
  Resolved["ResolvedTrackPlaybackStep\nslot + mute + fill + macros"]
  Evaluator["GeneratedSourceEvaluator"]
  Notes["GeneratedNote[]"]
  Events["NoteEvent[]"]
  Dispatch["Executor / routes / audio / MIDI"]

  Project --> Compiler
  Compiler --> Snapshot
  Snapshot --> PhraseBuffer
  Snapshot --> SourceProgram
  Snapshot --> ClipBuffer
  PhraseBuffer --> Resolved
  SourceProgram --> Resolved
  ClipBuffer --> Resolved
  Resolved --> Engine
  Engine --> Evaluator
  Evaluator --> Notes
  Notes --> Events
  Events --> Dispatch
```

## When To Add More Diagrams

Add a focused diagram when a feature changes one of these boundaries:

- a new persisted entity or `UUID` relationship;
- a new runtime buffer or hot-path lookup;
- a new state machine, such as clip history auditioning, audio recording, note repeat, or source-slot empty/clip/generator;
- a UX workflow where the sequence of decisions matters more than the entity shape.

Avoid one giant diagram for everything. The codebase is easier to reason about when persistent entities, runtime compilation, and user workflows stay separate.

## Related Pages

- [[application-overview]]
- [[document-model]]
- [[playback-data-path]]
- [[engine-architecture]]
- [[information-architecture-ux]]
- [[architecture-guardrails]]
