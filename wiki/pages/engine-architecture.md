---
title: "Engine Architecture"
category: "architecture"
tags: [engine, runtime, executor, midi, blocks, tick-clock]
summary: The current engine runtime: block protocol, typed streams, DAG executor, tick clock, prepare/dispatch split, routing layer, and the app-facing engine controller.
last-modified-by: codex
---

## Scope

`Sources/Engine/` is the runtime heart of the app. It is intentionally small and testable:

- typed stream values
- a narrow block protocol
- a registry of block kinds
- a DAG executor that drains UI commands at the top of each tick
- a BPM-driven software tick clock
- an `EventQueue` that decouples prepare from dispatch
- a `MacroCoordinator` that evaluates phrase layers into a `LayerSnapshot`
- a routing layer (`MIDIRouter`)
- an app-facing `EngineController`
- three core blocks: `note-generator`, `midi-out`, and `chord-context-sink`

This layer is musical/runtime code, not UI code and not document serialization.

## Module shape

```
Sources/Engine/
├── Block.swift
├── BlockRegistry.swift
├── CommandQueue.swift
├── EngineController.swift
├── EventQueue.swift
├── Executor.swift
├── LayerSnapshot.swift
├── MacroCoordinator.swift
├── MIDIRouter.swift
├── ScheduledEvent.swift
├── Stream.swift
├── TickClock.swift
└── Blocks/
    ├── ChordContextSink.swift
    ├── MidiOut.swift
    └── NoteGenerator.swift
```

## Block protocol

The block contract in [Block.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/Block.swift:1) is intentionally narrow:

- `tick(context:) -> [PortID: Stream]`
- `apply(paramKey:value:)`

Each block declares static `inputs` and `outputs` as `PortSpec` arrays, keyed by `StreamKind`. The executor uses those specs for wiring validation before playback begins.

The runtime command surface is:

- `setParam(blockID:paramKey:value:)`
- `setBPM(Double)`

That keeps the engine side decoupled from any SwiftUI control model. Views and controllers emit commands; blocks interpret them.

## Stream model

The stream system in [Stream.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/Stream.swift:1) uses one `Stream` enum rather than a deep generic type graph.

The six stream kinds are:

- `notes([NoteEvent])`
- `scalar(Double)`
- `chord(Chord)`
- `event(EventKind)`
- `gate(Bool)`
- `stepIndex(Int)`

`NoteEvent` is the important MVP payload: pitch, velocity, length in ticks, gate, and optional `voiceTag`.

## Executor

The executor in [Executor.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/Executor.swift:1) owns:

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

That "command drain at the top of the tick" rule is the key runtime contract, because it makes parameter changes deterministic from the UI side.

Validation happens at init time, not lazily mid-playback. The executor rejects:

- missing upstream ports
- stream kind mismatches
- cycles
- unknown upstream block ids

## Block registry

The registry in [BlockRegistry.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/BlockRegistry.swift:1) maps block kind ids to factories and metadata.

The shipped `registerCoreBlocks(_:)` helper registers:

- `note-generator`
- `midi-out`
- `chord-context-sink`

This is the stable seam for later plans. New block kinds should register through the same boundary instead of being hard-coded into the executor.

## Tick clock

The clock in [TickClock.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/TickClock.swift:1) is software-timed using `DispatchSourceTimer`.

Important details:

- BPM is mutable while running
- the timer is rescheduled when BPM changes
- tick callbacks receive `(tickIndex, now)`
- `now` is based on `ProcessInfo.processInfo.systemUptime`
- leeway is currently `1ms`

This is deliberately not render-thread or audio-clock driven yet. The current design favors a deterministic, testable software clock, with the event queue acting as the seam for later render-thread dispatch.

## Command queue

The command queue in [CommandQueue.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/CommandQueue.swift:1) is thread-safe, not lock-free.

Current contract:

- guarded by a private serial `DispatchQueue`
- FIFO append / drain behavior
- fixed capacity
- if full, new commands are dropped
- `droppedCount` records how many were rejected
- no command coalescing or "last wins" merge logic yet

That simplicity is intentional because the consumer is still a timer-driven runtime, not the audio render thread.

## Tick lifecycle

The current tick loop is split into two phases:

1. **Dispatch** drains the previous callback's `EventQueue` and fires sinks.
2. **Prepare** advances the executor for the upcoming step, evaluates phrase layers through the `MacroCoordinator`, and enqueues `ScheduledEvent`s for the next dispatch.

That split lives in [EngineController.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/EngineController.swift:1):

- `dispatchTick()`
- `prepareTick(upcomingStep:now:)`
- `processTick(tickIndex:now:)` as the coordinator between them

The current prepare/dispatch pair still runs inside one `TickClock` callback. The important architectural seam is the queue boundary, not the timer source. That gives later plans a safe place to move dispatch closer to the audio render thread without changing how events are prepared.

The coordinator side is documented in [[macro-coordinator]].

## Event queue

[EventQueue.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/EventQueue.swift:1) is a small FIFO guarded by `NSLock`. It currently carries:

- track AU events
- routed AU events
- chord-context broadcasts

MIDI still sends directly from `MidiOut` during prepare for now. A later plan can move MIDI into the queue without changing the prepare/dispatch boundary.

`ScheduledEvent.scheduledHostTime` is currently a forward-compatible placeholder. The queue drains immediately on dispatch; no sink is yet deferring work against host time.

## Routing layer

[MIDIRouter.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/MIDIRouter.swift:1) sits beside the DAG, not inside it. It consumes `RouterTickInput`s prepared by `EngineController`, matches them against document routes, and emits `RouterEvent`s back through the controller.

Today that means:

- routed MIDI still sends during prepare
- routed AU is enqueued into the `EventQueue`
- chord-context broadcasts are enqueued into the `EventQueue`

## Core blocks

### `note-generator`

[NoteGenerator.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/Blocks/NoteGenerator.swift:1) is the current MVP source block.

It emits a note stream from:

- `pitches`
- `stepPattern`
- `accentPattern`
- `velocity`
- `gateLength`

It is currently the "manual mono" happy path used by the UI.

### `midi-out`

[MidiOut.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/Blocks/MidiOut.swift:1) is the current sink block.

It:

- reads note events from the `notes` port
- schedules note-off events by future tick index
- converts `context.now` into CoreAudio host time
- sends MIDI through `MIDIClient.send`

This is the runtime link between the DAG and the CoreMIDI layer.

### `chord-context-sink`

[ChordContextSink.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/Blocks/ChordContextSink.swift:1) receives chord streams and forwards them into the routing and broadcast side of the engine. The actual chord-lane update now lands during dispatch via queued `ScheduledEvent.Payload.chordContextBroadcast`.

## Engine controller

[EngineController.swift](/Users/maxwilliams/dev/sequencer-ai/Sources/Engine/EngineController.swift:1) is the app-facing owner of the runtime.

It owns:

- `BlockRegistry`
- `CommandQueue`
- `TickClock`
- `EventQueue`
- `MacroCoordinator`
- the current `Executor`
- per-track generator ids and output runtimes
- route aggregation state
- transport state exposed to SwiftUI

Its responsibilities are:

- build the default per-track pipeline for the current document model
- apply document changes into block params or rebuild shape when needed
- start and stop transport
- dispatch queued events for the current step
- prepare the next step's events
- fan note events out to MIDI sinks or audio sinks
- evaluate phrase layers into a lightweight snapshot used during prepare

This is the seam between document/UI state and the lower runtime.

## Dependency direction

The current dependency picture is:

```
UI → Engine
Engine → Document
Engine → MIDI
Engine → Audio (through playback sink use)
Document → (independent)
```

The document model does not import the engine, and the executor does not know about SwiftUI.

## Test coverage

The current suite has broad unit and integration coverage for this layer:

- block protocol behavior
- stream value semantics
- registry registration
- command queue concurrency behavior
- tick clock timing tolerances
- event queue behavior
- macro-coordinator mute evaluation
- `note-generator`
- `midi-out`
- `chord-context-sink`
- end-to-end routing and controller behavior

Run with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme SequencerAI -destination 'platform=macOS' test
```

## Related pages

- [[project-layout]]
- [[midi-layer]]
- [[document-model]]
- [[macro-coordinator]]
