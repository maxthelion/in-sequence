---
title: "Engine Architecture"
category: "architecture"
tags: [engine, runtime, executor, midi, blocks, tick-clock]
summary: The shipped Plan 1 engine runtime: block protocol, typed streams, DAG executor, software tick clock, command queue, and the app-facing engine controller.
last-modified-by: codex
---

## Scope

`Sources/Engine/` is the runtime heart of the app shipped in Plan 1. It is intentionally small and testable:

- typed stream values
- a narrow block protocol
- a registry of block kinds
- a DAG executor that drains UI commands at the top of each tick
- a BPM-driven software tick clock
- an app-facing `EngineController`
- two core blocks: `note-generator` and `midi-out`

This layer is musical/runtime code, not UI code and not document serialization.

## Module shape

```
Sources/Engine/
├── Block.swift
├── Stream.swift
├── Executor.swift
├── BlockRegistry.swift
├── TickClock.swift
├── CommandQueue.swift
├── EngineController.swift
└── Blocks/
    ├── NoteGenerator.swift
    └── MidiOut.swift
```

## Block protocol

The block contract in [Block.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/Block.swift:1) is intentionally narrow:

- `tick(context:) -> [PortID: Stream]`
- `apply(paramKey:value:)`

Each block declares static `inputs` and `outputs` as `PortSpec` arrays, keyed by `StreamKind`. The executor uses those specs for wiring validation before playback begins.

The runtime command surface is:

- `setParam(blockID:paramKey:value:)`
- `setBPM(Double)`

That keeps the engine side decoupled from any SwiftUI control model. Views and controllers emit commands; blocks interpret them.

## Stream model

The shipped stream system in [Stream.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/Stream.swift:1) uses one `Stream` enum rather than a deep generic type graph.

The six stream kinds are:

- `notes([NoteEvent])`
- `scalar(Double)`
- `chord(Chord)`
- `event(EventKind)`
- `gate(Bool)`
- `stepIndex(Int)`

`NoteEvent` is the important MVP payload: pitch, velocity, length in ticks, gate, and optional `voiceTag`.

## Executor

The executor in [Executor.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/Executor.swift:1) owns:

- graph validation
- topological ordering
- per-tick input gathering
- command draining
- BPM state
- block output collection

The ordering rule is simple and important:

1. drain commands
2. apply any pending param / BPM changes
3. run blocks in topological order
4. increment the tick counter

That "command drain at the top of the tick" rule is the key Plan 1 contract, because it makes parameter changes deterministic from the UI side.

Validation happens at init time, not lazily mid-playback. The executor rejects:

- missing upstream ports
- stream kind mismatches
- cycles
- unknown upstream block ids

## Block registry

The registry in [BlockRegistry.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/BlockRegistry.swift:1) maps block kind ids to factories and metadata.

Plan 1 ships a `registerCoreBlocks(_:)` helper that registers:

- `note-generator`
- `midi-out`

This is the stable seam for later plans. New block kinds should register through the same boundary instead of being hard-coded into the executor.

## Tick clock

The clock in [TickClock.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/TickClock.swift:1) is software-timed using `DispatchSourceTimer`.

Important details:

- BPM is mutable while running
- the timer is rescheduled when BPM changes
- tick callbacks receive `(tickIndex, now)`
- `now` is based on `ProcessInfo.processInfo.systemUptime`
- leeway is currently `1ms`

This is deliberately not render-thread / audio-clock driven yet. The design choice for Plan 1 was to ship a deterministic, testable software clock first and defer realtime-thread concerns to the audio-engine phase.

## Command queue

The command queue in [CommandQueue.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/CommandQueue.swift:1) is thread-safe, not lock-free.

Current contract:

- guarded by a private serial `DispatchQueue`
- FIFO append / drain behavior
- fixed capacity
- if full, new commands are dropped
- `droppedCount` records how many were rejected
- no command coalescing or "last wins" merge logic yet

That last point matters: the queue is intentionally simple for Plan 1 because the consumer is not the audio render thread yet.

## Core blocks

### `note-generator`

[NoteGenerator.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/Blocks/NoteGenerator.swift:1) is the current MVP source block.

It emits a note stream from:

- `pitches`
- `stepPattern`
- `accentPattern`
- `velocity`
- `gateLength`

It is currently the "manual mono" happy path used by the UI.

### `midi-out`

[MidiOut.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/Blocks/MidiOut.swift:1) is the current sink block.

It:

- reads note events from the `notes` port
- schedules note-off events by future tick index
- converts `context.now` into CoreAudio host time
- sends MIDI through `MIDIClient.send`

This is the runtime link between the DAG and the CoreMIDI layer.

## Engine controller

[EngineController.swift](/Users/maxwilliams/dev/sequencer-ai/.codex-worktree/Sources/Engine/EngineController.swift:1) is the app-facing owner of the runtime.

It owns:

- `BlockRegistry`
- `CommandQueue`
- `TickClock`
- the current `Executor`
- per-track generator ids and output runtimes
- transport state exposed to SwiftUI

Its responsibilities are:

- build the default per-track pipeline for the current document model
- apply document changes into block params or rebuild shape when needed
- start / stop transport
- process each tick
- fan note events out to MIDI sinks or audio sinks

This is the seam between document/UI state and the lower runtime.

## Dependency direction

The current dependency picture is:

```
UI → Engine
Engine → MIDI
Engine → Audio (through playback sink use)
Document → (independent)
```

The document model does not import the engine, and the executor does not know about SwiftUI.

## Test coverage

Plan 1 shipped with broad unit and integration coverage for this layer:

- block protocol behavior
- stream value semantics
- registry registration
- command queue concurrency behavior
- tick clock timing tolerances
- `note-generator`
- `midi-out`
- end-to-end `note-generator → midi-out`
- controller wiring and transport behavior

Run with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme SequencerAI -destination 'platform=macOS' test
```

## Related pages

- [[project-layout]]
- [[midi-layer]]
- [[document-model]]
