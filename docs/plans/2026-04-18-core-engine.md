# Core Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a runnable pipeline engine that ticks at a user-configurable BPM, executes a small DAG of typed blocks per tick, emits MIDI on a virtual CoreMIDI destination, and receives parameter updates from the UI thread through a lock-free command queue. Verified end-to-end via XCTest: the test wires `note-generator → midi-out`, drives the engine for N ticks, and asserts that M expected MIDI events arrive on a virtual input.

**Architecture:** One Swift module (`Engine`) that owns the executor, block registry, typed streams, and command queue. Blocks conform to a narrow protocol (`tick(context:) -> OutputBundle` + `apply(_ command: Command)`) — a block reads typed streams from the `TickContext`, returns its outputs, and handles parameter-update commands out-of-band. The executor holds a topologically-sorted block list and runs them in order per tick, drains any queued UI commands at the top of each tick, and dispatches each command to the target block by `BlockID`. The `TickClock` fires at the step interval corresponding to the current BPM using a `DispatchSourceTimer` (MVP — replaced by an audio-clock-driven source in the audio-engine plan, sub-spec 10). Parameter changes from the UI go through a `CommandQueue` drained at the top of each tick. No audio engine integration in this plan — the tick clock is software-timed, sample-accurate scheduling lands when the audio-side plan arrives.

**Design decisions deliberately taken (flagged because they could be litigated later):**

- **`CommandQueue` is thread-safe but not lock-free for this plan.** The spec's "lock-free" requirement exists because the consumer runs on the audio render thread, which Plan 1 does not. A `DispatchQueue`-serialised ring buffer meets every Plan-1 test and avoids an `Atomics` package dependency. The lock-free re-implementation is folded into Plan 10 (audio engine) when the realtime-thread constraint actually bites. The `CommandQueue` public API is chosen so the swap is a drop-in replacement.
- **`Stream` is a fat enum, not a set of distinct types.** Type-checking of port connections is runtime, not compile-time. Full compile-time typing (one value type per stream kind + generic `PortSpec`) is a deeper refactor and doesn't ship more working software in Plan 1. Revisit in Plan 2 when we have more blocks and the cost of runtime checks is actually measurable.
- **`TickContext.inputs` is a dict, constructed per-tick per-block.** Yes, this allocates. We are not on the render thread. Plan 10 will revisit alongside the audio-clock migration — an inline-storage alternative is cheap once the hot-path constraint exists.

**Tech Stack:** Swift 5.9+, Foundation (DispatchQueue, DispatchSourceTimer), CoreMIDI via `MIDIClient` (**extended in this plan — see Task 1**), XCTest.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — sub-spec 1 (Core engine). Scope-shave vs. spec: this plan ships tick-loop + registry + streams + command-queue + `note-generator` source + `midi-out` sink. The remaining spec-listed blocks (`clip-reader`, `force-to-scale`, `quantise-to-chord`, `interpret`) are deferred to a follow-up **Plan 2: Core blocks** because (a) `clip-reader` depends on a clip data model that belongs with the phrase/macro plan (spec sub-spec 2), (b) `interpret` reads abstract macro rows that also belong there, and (c) splitting produces working, tagged software at each milestone.

**Why not audio-clock-driven ticks yet:** Audio-engine integration is a separate spec sub-spec (10). Starting with a `DispatchSourceTimer` gives us a testable engine today; swapping the clock source later is a local change because `TickClock` is injected into the executor via a protocol, not hard-coded. The executor itself is clock-agnostic.

**Environment note:** Same Xcode-16 / `DEVELOPER_DIR` discipline as Plan 0. All `xcodebuild` commands prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## File Structure

All paths relative to project root.

```
Sources/
  MIDI/
    MIDIClient.swift          # Plan 0; this plan adds a `send(_:to:)` method
    MIDIPacketBuilder.swift   # NEW — constructs MIDIPacketList values for send
  Engine/
    Block.swift               # Block protocol, BlockID, PortSpec, TickContext, Command
    Stream.swift              # Typed stream value types
    Executor.swift            # DAG executor + command-queue drain + dispatch to blocks
    BlockRegistry.swift       # id → factory, ParamValue-typed params
    TickClock.swift           # BPM-driven software tick source
    CommandQueue.swift        # Thread-safe queue (DispatchQueue-serialised; MVP)
    EngineController.swift    # App-facing owner of Executor + TickClock + Queue + Registry
    Blocks/
      NoteGenerator.swift     # Source: emits note-stream
      MidiOut.swift           # Sink: consumes note-stream → MIDIClient
Tests/
  SequencerAITests/
    MIDI/
      MIDIPacketBuilderTests.swift
      MIDIClientSendTests.swift
    Engine/
      StreamTests.swift
      BlockProtocolTests.swift
      ExecutorTests.swift
      BlockRegistryTests.swift
      TickClockTests.swift
      CommandQueueTests.swift
      NoteGeneratorTests.swift
      MidiOutTests.swift
      EngineIntegrationTests.swift
      EngineControllerTests.swift
```

`project.yml` gets an `Engine` group under `Sources/` so files are picked up automatically.

Dependency direction (per `wiki/pages/project-layout.md`, updated by this plan):

```
App → UI → Engine / MIDI / Platform / Document
            Engine   → MIDI (uses MIDIClient from Plan 0)
            Engine   → (nothing else project-internal)
            MIDI     → (nothing)
            Document → (nothing — Engine does not touch the document model here)
```

---

## Task 1: Extend `MIDIClient` with a transmit path

**Scope:** Plan 0 shipped MIDI client creation, enumeration, and virtual endpoints — but no `send`. This plan's `midi-out` block depends on being able to push MIDI to a `MIDIEndpoint`, so this task closes the hole before any block code depends on it. Comes FIRST so every later task can assume it exists.

Two pieces:

1. **`MIDIPacketBuilder.swift`** (new, in `Sources/MIDI/`) — a value-type builder that constructs a `MIDIPacketList` for `{note-on, note-off, cc}` payloads. Avoids the error-prone C-style `MIDIPacketListAdd` dance at every call site.
2. **`MIDIClient.send(packet:to:)`** (new method on existing `MIDIClient`) — routes a `MIDIPacketList` either via `MIDIReceived` (if the target is a virtual source this client created) or via `MIDISend` to a port (if the target is an external or virtual destination).

**Files:**
- Create: `Sources/MIDI/MIDIPacketBuilder.swift`
- Modify: `Sources/MIDI/MIDIClient.swift` — add `send(_:to:)` + a lazy output port
- Create: `Tests/SequencerAITests/MIDI/MIDIPacketBuilderTests.swift`
- Create: `Tests/SequencerAITests/MIDI/MIDIClientSendTests.swift`

**Tests:**

1. `MIDIPacketBuilderTests`: builds a note-on + note-off pair into a packet list; asserts the list's first packet's 3-byte payload matches `[0x90 | channel, pitch, velocity]`, second packet's matches `[0x80 | channel, pitch, 0]`, and the second packet's timestamp is strictly later.
2. `MIDIClientSendTests`:
   - Create a `MIDIClient` "A", a virtual destination `A.dest`. Create a separate `MIDIClient` "B", create an input port that records packets, connect the port to `A.dest`. `A.send(packet, to: A.dest)` → `B` sees the packet.
   - (Loopback via two clients avoids CoreMIDI's own-source-filter behaviour.)

**Acceptance:** `Sources/MIDI/MIDIClient.swift` has a `send` method referenced below in Task 9. Tests green.

Key rule: this task is a prerequisite for Task 9 (`midi-out`). Do not start Task 9 before Task 1 is committed.

- [ ] MIDIPacketBuilder tests (one note pair)
- [ ] MIDIPacketBuilder impl
- [ ] MIDIClientSendTests (2-client loopback)
- [ ] MIDIClient.send impl + lazy output port
- [ ] Green `xcodebuild test`
- [ ] Commit: `feat(midi): transmit path — MIDIPacketBuilder + MIDIClient.send`

---

## Task 2: Typed streams

**Scope:** Create `Sources/Engine/` + `Stream.swift`. Define the six stream value types from the spec as plain Swift types. No executor, no blocks yet — this task ships just the typed stream primitives so later tasks have something to read/write.

**Files:**
- Create: `Sources/Engine/Stream.swift`
- Create: `Tests/SequencerAITests/Engine/StreamTests.swift`
- Modify: `project.yml` (add `Sources/Engine` group)

**Types to define:**

```swift
public struct NoteEvent: Equatable, Sendable {
    public let pitch: UInt8          // MIDI note 0…127
    public let velocity: UInt8       // 0…127
    public let length: UInt16        // ticks
    public let gate: Bool
    public let voiceTag: String?     // nil for non-drum tracks
}

public enum Stream: Equatable, Sendable {
    case notes([NoteEvent])          // note-stream: 0+ events at this tick
    case scalar(Double)              // scalar-stream: 0.0…1.0
    case chord(Chord)                // chord-stream
    case event(EventKind)            // event-stream: trigger
    case gate(Bool)                  // gate-stream
    case stepIndex(Int)              // step-index-stream
}

public struct Chord: Equatable, Sendable { … }
public enum EventKind: Equatable, Sendable { case fillFlag, barTick, custom(String) }
```

**Acceptance:** XCTest `StreamTests` creates each variant, asserts `Equatable`, asserts `Sendable` (via `@Sendable` closure round-trip). All types are value types.

- [ ] Write `StreamTests` (6 cases, one per variant)
- [ ] Write `Stream.swift` minimum to pass
- [ ] `xcodebuild test` green
- [ ] Commit: `feat(engine): typed stream value types`

---

## Task 3: Block protocol + TickContext + Command

**Scope:** The narrow contract every block satisfies. Two methods: `tick(context:)` reads input streams and returns outputs; `apply(_ command:)` handles parameter-update commands delivered from the UI via the command queue. The `Command` enum is defined here (not in CommandQueue) because it's the block's contract.

**Files:**
- Create: `Sources/Engine/Block.swift`
- Create: `Tests/SequencerAITests/Engine/BlockProtocolTests.swift`

**Design:**

```swift
public typealias BlockID = String
public typealias PortID = String

public struct PortSpec: Equatable, Sendable {
    public let id: PortID
    public let streamKind: StreamKind
    public let required: Bool       // false = accepts nil
}

public enum StreamKind: String, Sendable {
    case notes, scalar, chord, event, gate, stepIndex
}

public enum ParamValue: Equatable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case integers([Int])    // pitch lists, step patterns (Bool packed), etc.
}

public enum Command: Sendable {
    case setParam(blockID: BlockID, paramKey: String, value: ParamValue)
    case setBPM(Double)
}

public struct TickContext {
    public let tickIndex: UInt64
    public let bpm: Double
    public let inputs: [PortID: Stream]   // streams fed into THIS block
    public let now: TimeInterval          // monotonic tick timestamp
}

public protocol Block: AnyObject {
    var id: BlockID { get }
    static var inputs: [PortSpec] { get }
    static var outputs: [PortSpec] { get }
    func tick(context: TickContext) -> [PortID: Stream]
    /// Apply a param update. Blocks reject unknown keys by doing nothing;
    /// the executor logs unknown keys via `os_log` at debug level.
    func apply(paramKey: String, value: ParamValue)
}
```

**Acceptance:** A trivial test block emits `.scalar(0.5)` on output `"value"`. After `apply(paramKey: "level", value: .number(0.8))`, its next tick emits `.scalar(0.8)`. An unknown `paramKey` causes no change and no crash.

- [ ] Write test for the trivial block — tick, apply, tick again, unknown-key apply
- [ ] Write `Block.swift`
- [ ] Green
- [ ] Commit: `feat(engine): block protocol + TickContext + Command`

---

## Task 4: Executor (topological tick + command drain)

**Scope:** The piece that runs a DAG of blocks per tick. Takes a `[BlockID: Block]` (order-agnostic) and a wiring table; computes topological order at init; cycle detection at load-time.

Per `tick()`:
1. Drain the `CommandQueue` (passed in via init). For each `.setParam(blockID:paramKey:value:)`, look up `blocks[blockID]` and call `apply(paramKey:value:)`. For `.setBPM`, update a local `currentBPM` and forward to the next `tick()` call.
2. For each block in topological order, gather its inputs, call `block.tick(context:)`, stash outputs.

**Files:**
- Create: `Sources/Engine/Executor.swift`
- Create: `Tests/SequencerAITests/Engine/ExecutorTests.swift`

**Public API:**

```swift
public final class Executor {
    public init(
        blocks: [BlockID: Block],
        wiring: [BlockID: [PortID: (BlockID, PortID)]],
        commandQueue: CommandQueue
    ) throws
    public func tick(now: TimeInterval) -> [BlockID: [PortID: Stream]]
    public var currentBPM: Double { get }

    public enum Error: Swift.Error, Equatable {
        case cycleDetected(path: [BlockID])
        case missingUpstream(blockID: BlockID, portID: PortID)
        case streamKindMismatch(blockID: BlockID, portID: PortID, expected: StreamKind, got: StreamKind)
        case unknownBlockID(BlockID)
    }
}
```

**Tests cover:**

1. Single-block graph: one source block, one tick, returns its output.
2. Two-block chain: source → transform, transform reads source's output.
3. Cycle detection throws at init.
4. Missing upstream throws at init.
5. Stream-kind mismatch throws at init.
6. `tickIndex` increments on each `tick()`.
7. **Command drain — param**: enqueue `.setParam(blockID: "b", paramKey: "k", value: .number(0.8))` before `tick`; verify `b.apply` was called (use a spy block).
8. **Command drain — BPM**: enqueue `.setBPM(240)`; verify `currentBPM == 240` after `tick`.
9. **Command for unknown block**: enqueue `.setParam(blockID: "missing", ...)`; `tick()` does not throw; a debug log entry exists. No crash, no stale command.

- [ ] Write failing tests (9 cases)
- [ ] Implement topological sort
- [ ] Implement `tick` with command drain at top
- [ ] Implement cycle / wiring / type-check validation
- [ ] Green
- [ ] Commit: `feat(engine): DAG executor with command-drain tick`

---

## Task 5: BlockRegistry

**Scope:** String-keyed factory. UI/document code creates a block by its kind identifier (e.g. `"note-generator"`) so blocks can be serialised without type-erasure gymnastics. The registry reports each kind's `PortSpec`s so the graph editor can type-check wiring before calling the executor. Params passed to the factory are `[String: ParamValue]` — the same value type used by `Command.setParam`, so there's one canonical param vocabulary.

**Files:**
- Create: `Sources/Engine/BlockRegistry.swift`
- Create: `Tests/SequencerAITests/Engine/BlockRegistryTests.swift`

**Public API:**

```swift
public struct BlockKind: Equatable, Sendable {
    public let id: String                   // "note-generator", "midi-out"
    public let inputs: [PortSpec]
    public let outputs: [PortSpec]
    public let make: (BlockID, [String: ParamValue]) -> Block
}

public final class BlockRegistry {
    public init()
    /// Throws `RegistryError.duplicate(kindID)` if `kind.id` is already registered.
    /// Rationale: silent replacement hides bugs; throw-and-log is the safer default.
    public func register(_ kind: BlockKind) throws
    public func kinds() -> [BlockKind]
    public func make(kindID: String, blockID: BlockID, params: [String: ParamValue] = [:]) -> Block?

    public enum RegistryError: Swift.Error, Equatable { case duplicate(String) }
}
```

**Tests:**

1. Register a test kind, retrieve by `kindID`, make an instance.
2. Unknown `kindID` returns `nil`.
3. `kinds()` reflects every registration (order not asserted).
4. Double-registration of the same `kindID` throws `RegistryError.duplicate`.

- [ ] Tests for the four cases
- [ ] Implement registry
- [ ] Green
- [ ] Commit: `feat(engine): block registry`

---

## Task 6: TickClock (BPM-driven software tick source)

**Scope:** A serial-dispatch-queue-backed timer that fires a tick handler at the interval corresponding to the current BPM and `stepsPerBar`. Default `stepsPerBar = 16`; time signature 4/4 (the `4` in the formula is beats-per-bar, not a magic number — comment it inline).

Tick interval = `60.0 / bpm / stepsPerBar * beatsPerBar` seconds, where `beatsPerBar = 4`.

The clock can be started, stopped, and have its BPM changed while running (next tick uses the new BPM). The tick handler is called with the monotonic-clock timestamp and the tick index.

**Files:**
- Create: `Sources/Engine/TickClock.swift`
- Create: `Tests/SequencerAITests/Engine/TickClockTests.swift`

**Public API:**

```swift
public final class TickClock {
    public init(stepsPerBar: Int = 16)
    public var bpm: Double { get set }
    public func start(onTick: @escaping (UInt64, TimeInterval) -> Void)
    public func stop()
    public var isRunning: Bool { get }
}
```

**Tests:** Assert on **inter-tick intervals** via the `now` timestamps the handler receives, not on total count over a window (count-over-window cannot distinguish a correct-but-jittery clock from a systematically-wrong one).

1. Start at 240 BPM × 16 steps/bar → expected interval 62.5ms. Record 10 consecutive tick timestamps; assert every delta is within ±8ms of 62.5ms. Use `DispatchSourceTimer` with explicit `leeway: .milliseconds(1)`.
2. Stop inside handler — no further `onTick` calls after `stop()` returns; verified by setting a flag in the handler and asserting it remains false for 200ms after stop.
3. Change BPM mid-run — record the delta across the change; asserts the first post-change delta matches the new expected interval within ±8ms.
4. Tick index starts at 0 and increments monotonically (no gaps).

- [ ] Tests (assert on intervals, not counts; tolerances explicit)
- [ ] Implementation using `DispatchSource.makeTimerSource` with leeway 1ms
- [ ] Green — tests may be sensitive under CI load; if flake observed, raise tolerance rather than lowering assertion strictness (never test "passes if timer fires at all")
- [ ] Commit: `feat(engine): BPM-driven tick clock`

---

## Task 7: CommandQueue (thread-safe UI → engine queue)

**Scope:** A fixed-capacity, thread-safe FIFO queue for parameter updates from the UI thread to the engine thread. The engine drains the queue at the top of each `tick`. `Command` is defined in Task 3 (it's the block's contract).

**Design choice (Plan 1 MVP):** `DispatchQueue`-serialised array, `capacity`-bounded. Simpler than a lock-free ring buffer; meets every test. The lock-free SPSC re-implementation lands in Plan 10 (audio engine) when the consumer actually runs on the render thread. Keep the public API below frozen so Plan 10 is a drop-in replacement.

**Files:**
- Create: `Sources/Engine/CommandQueue.swift`
- Create: `Tests/SequencerAITests/Engine/CommandQueueTests.swift`

**Public API:**

```swift
public final class CommandQueue {
    public init(capacity: Int = 1024)
    @discardableResult
    public func enqueue(_ command: Command) -> Bool   // false = full, dropped
    public func drainAll() -> [Command]                // FIFO; clears queue
    public var droppedCount: UInt64 { get }            // cumulative overflow counter
}
```

**Tests:**

1. Enqueue N < capacity → drain returns N in FIFO order.
2. Enqueue past capacity → returns false; `droppedCount` increments; drain doesn't include dropped entries.
3. Enqueue from background queue, drain from main → no crashes, all enqueued commands appear (order within a producer is preserved).
4. Stress: 1000 enqueues interleaved with 10 drains across two queues; all commands accounted for (enqueued == drained + dropped).

- [ ] Tests (include the concurrency test using `XCTestExpectation`)
- [ ] Implement with a serial `DispatchQueue` guarding a `[Command]`
- [ ] Green
- [ ] Commit: `feat(engine): thread-safe command queue`

---

## Task 8: NoteGenerator source block

**Scope:** A block with no inputs and one output (`notes: .notes`). Configurable via params: `pitches: [UInt8]` (default C major scale 60,62,64,65,67,69,71,72), `stepPattern: [Bool]` (default all true), `velocity: UInt8` (default 100), `gateLength: UInt16` (default 4 ticks).

Per tick, emits `Stream.notes([NoteEvent(...)])` if `stepPattern[tickIndex % stepPattern.count]` is true; else emits `Stream.notes([])`.

**Files:**
- Create: `Sources/Engine/Blocks/NoteGenerator.swift`
- Create: `Tests/SequencerAITests/Engine/NoteGeneratorTests.swift`

**Tests:**

1. Default config, 16 ticks → 16 notes (all steps true). Pitches cycle through `pitches`.
2. `stepPattern = [true, false, true, false]`, 8 ticks → 4 notes.
3. `stepPattern = [false]` → zero notes ever.
4. Block registers in the `BlockRegistry` under `"note-generator"`.

- [ ] Tests
- [ ] Implementation
- [ ] Registry registration in a module-level `registerCoreBlocks(_:)` helper in `BlockRegistry.swift`
- [ ] Green
- [ ] Commit: `feat(engine): note-generator source block`

---

## Task 9: MidiOut sink block

**Scope:** A block with one input (`notes: .notes`, required) and no outputs. Consumes `Stream.notes(...)` each tick and emits MIDI to a configured `MIDIEndpoint` via `MIDIClient.send(...)` (the method shipped in Task 1).

Configurable via params: `channel: UInt8` (default 0 = MIDI ch 1). Note-off scheduling: `MidiOut` queues a note-off into its internal tick-indexed schedule at `tickIndex + note.length`. On subsequent ticks it sends any note-offs whose scheduled tick has arrived.

**Files:**
- Create: `Sources/Engine/Blocks/MidiOut.swift`
- Create: `Tests/SequencerAITests/Engine/MidiOutTests.swift`

**Tests:** Use the Plan 0 retrospective's validated pattern: **two `MIDIClient` instances**, one creating a virtual destination (observable input port on the other) and the MidiOut block sending via the first client's output port. This is the pattern that was proven in Plan 0's `test_created_virtual_output_appears_in_destinations` after the Task-9 retrospective rename. **Do not repeat the "virtual source listens to itself" mistake** — a `MIDISourceCreate`-created source has no callback.

1. MidiOut receives `.notes([1 NoteEvent(length=4)])` at tickIndex=0 → client sees 1 note-on. At tickIndex=4 → client sees the matching note-off.
2. MidiOut receives `.notes([])` → nothing sent, no scheduled note-offs pending.
3. MidiOut receives 3 notes (chord) → 3 note-ons followed by 3 note-offs after their gate length.
4. MidiOut receives notes at channel=5 → note-on's status byte is `0x95` (0x90 | 0x05).
5. Block registers in registry under `"midi-out"`.

- [ ] Tests using two-client loopback
- [ ] Implementation (depends on MIDIClient.send from Task 1)
- [ ] Green
- [ ] Commit: `feat(engine): midi-out sink block`

---

## Task 10: End-to-end integration

**Scope:** Prove the whole stack works together. Wire `note-generator → midi-out`, drive the executor from the `TickClock`, observe MIDI events on a virtual destination owned by a **second** `MIDIClient`, send a command-queue `setBPM` and `setParam` mid-run, verify the effects.

**Files:**
- Create: `Tests/SequencerAITests/Engine/EngineIntegrationTests.swift`

**Scenario (corrected per Plan 0 retrospective on virtual endpoint direction):**

```swift
func test_engine_emits_expected_midi_for_N_ticks() throws {
    // Two clients: producer owns the MidiOut target; observer records.
    let producerClient = try MIDIClient(name: "engine-test-producer")
    let observerClient = try MIDIClient(name: "engine-test-observer")
    let producerDest = try producerClient.createVirtualInput(name: "engine-dest")

    // Observer connects an input port to producerDest and records packets.
    let recorder = MIDIPacketRecorder()
    try observerClient.connect(source: producerDest, to: recorder)

    let gen = NoteGenerator(id: "gen", params: [
        "pitches": .integers([60]),
        "stepPattern": .integers([1]),          // always-on
        "velocity": .number(100),
        "gateLength": .number(4)
    ])
    let out = MidiOut(id: "out", params: ["channel": .number(0)])
    out.endpoint = producerDest    // direct property (not in ParamValue world)
    out.client = producerClient

    let queue = CommandQueue(capacity: 128)
    let executor = try Executor(
        blocks: ["gen": gen, "out": out],
        wiring: ["out": ["notes": ("gen", "notes")]],
        commandQueue: queue
    )

    let clock = TickClock(stepsPerBar: 16)
    queue.enqueue(.setBPM(480))    // 62.5ms / 4 = 15.625ms per tick
    clock.start { _, now in _ = executor.tick(now: now) }
    // Wait 500ms → expect ~32 ticks = ~32 notes.
    let exp = expectation(description: "notes arrived")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        clock.stop()
        exp.fulfill()
    }
    wait(for: [exp], timeout: 1.0)
    XCTAssertGreaterThanOrEqual(recorder.noteOnCount, 25, "expected ~32 notes in 500ms")
}
```

**Test scenarios:**

1. 500ms run at 480 BPM × 16 → ≥25 note-ons observed on the other client's port.
2. `setBPM(120)` mid-run → observed inter-note interval roughly quadruples.
3. `setParam(blockID: "gen", paramKey: "pitches", value: .integers([60, 64, 67]))` mid-run → observed pitches shift to the new set (sample the recorder's pitch history after the change).

- [ ] Harness: `MIDIPacketRecorder` (simple test helper; owns a `MIDIInputPort` + array of received packets)
- [ ] Test scenario 1
- [ ] Test scenario 2 (BPM change)
- [ ] Test scenario 3 (param change)
- [ ] Green
- [ ] Commit: `test(engine): end-to-end note-generator → midi-out integration`

---

## Task 11: Wire Engine into the app shell

**Scope:** Expose the engine to the SwiftUI app: a single `EngineController` (`@Observable`, macOS 14+) that owns an `Executor`, `TickClock`, `CommandQueue`, and `BlockRegistry`. Bound to Play/Stop in `TransportBar.swift` (Plan 0 placeholder).

**Where does the hard-coded `note-gen → midi-out` pipeline live?** In `EngineController.buildDefaultPipeline()` — a private method called during `EngineController.init()`. Rationale: the document model (`SeqAIDocumentModel`) should NOT yet encode pipelines; that's phrase-scoped and belongs to sub-spec 2 (phrase model). Keeping the pipeline inside `EngineController` means Plan 2 can lift it into the document without rewriting anything in `SeqAIDocumentModel`.

The Architecture header's claim that "Engine does not touch the document model here" holds.

**Files:**
- Create: `Sources/Engine/EngineController.swift`
- Modify: `Sources/UI/TransportBar.swift` (wire Play/Stop to `EngineController`)
- Modify: `Sources/App/SequencerAIApp.swift` (construct the controller; pass via environment)
- Create: `Tests/SequencerAITests/Engine/EngineControllerTests.swift`

**Tests:**

1. `EngineController.init()` registers core blocks and builds the default pipeline without throwing.
2. `start()` then `isRunning == true`; `stop()` then `false`.
3. After `start()`, `setBPM(120)` via the controller's facade makes its way into `executor.currentBPM` within 2 ticks.

- [ ] EngineControllerTests
- [ ] EngineController implementation (including `buildDefaultPipeline`)
- [ ] TransportBar wiring
- [ ] App entry wiring
- [ ] Manual smoke test: hit Play, observe MIDI on a DAW / MIDI monitor; note the observation in the commit message
- [ ] Green `xcodebuild test`
- [ ] Commit: `feat(engine): wire engine into app shell + transport`

---

## Task 12: Wiki update

**Scope:** Add `wiki/pages/engine-architecture.md` describing the block protocol, stream types, executor contract, command-queue contract, and tick-clock approach. Update `wiki/pages/project-layout.md` to reflect the new `Engine/` module and its position in the dependency graph.

**Files:**
- Create: `wiki/pages/engine-architecture.md`
- Modify: `wiki/pages/project-layout.md`

Dispatched via the `wiki-maintainer` agent. The agent's scope is `wiki/pages/` only — it cannot touch `Sources/` or docs. Must land in the same tag as the code (per Plan 0 template).

- [ ] Wiki page covers: block protocol + apply(command), 6 stream kinds, executor ordering + command-drain-at-top, tick-clock model (and why it's software-timed for now), command-queue contract (capacity, dropped-count, last-wins semantics)
- [ ] `project-layout.md` gains the `Engine` module row + updated dependency-direction diagram
- [ ] Commit: `docs(wiki): engine architecture + project-layout update`

---

## Task 13: Tag + mark completed

- [ ] Replace every `- [ ]` in this file with `- [x]` for steps actually completed
- [ ] Add `Status: ✅ Completed YYYY-MM-DD. Tag v0.0.2-core-engine at <SHA>.` after `Parent spec`
- [ ] Commit: `docs(plan): mark 1-core-engine completed`
- [ ] Tag: `git tag -a v0.0.2-core-engine -m "Core engine complete: tick loop + executor + streams + command queue + note-gen + midi-out + shell wiring"`

---

## Spec coverage + architectural-claim traceability (self-review)

Each architectural claim in the header maps to the task that tests it. If you discover a claim below without a task, fix the plan — don't hope the implementer improvises.

| Spec item (sub-spec 1) / architectural claim | Task | Notes |
|---|---|---|
| MIDI transmit path (`MIDIClient.send`) | Task 1 | Prerequisite; must land before Task 9 |
| Typed streams | Task 2 | Fat enum; runtime-checked (tradeoff documented in header) |
| Block protocol + `apply(command:)` | Task 3 | `Command` enum colocated with the protocol |
| Pipeline DAG executor | Task 4 | Cycle/wiring/type validation at init |
| **Executor drains CommandQueue at top of tick** | Task 4 (test #7-9) | Closes the "queue sits there unused" gap |
| **Executor dispatches `.setParam` to the right block via `apply`** | Task 4 (test #7) | Spy-block verifies `apply` called |
| **Executor tracks BPM updates** | Task 4 (test #8) | `setBPM` via queue mutates `currentBPM` |
| Block registry w/ typed `ParamValue` params | Task 5 | Throws on duplicate registration |
| Tick clock @ `60/bpm/stepsPerBar * 4` | Task 6 | Interval-delta assertions (not count-over-window) |
| Command queue (thread-safe, not lock-free in Plan 1) | Task 7 | Tradeoff documented in header |
| `note-generator` source | Task 8 | Registers under `"note-generator"` |
| `midi-out` sink | Task 9 | Uses Task 1's `send`; two-client loopback tests |
| End-to-end: tick → gen → out → observable MIDI | Task 10 | 3 scenarios (notes, BPM change, param change) |
| Engine embedded in app shell (`EngineController`) | Task 11 | Owns pipeline; document model untouched |
| Wiki + project-layout updated | Task 12 | Must land in same tag |
| Tag `v0.0.2-core-engine` | Task 13 |  |
| `clip-reader` | **Deferred** — Plan 2 | depends on clip data model from sub-spec 2 |
| `force-to-scale` | **Deferred** — Plan 2 | pure transform, groups with block library |
| `quantise-to-chord` | **Deferred** — Plan 2 | depends on chord-context plumbing from sub-spec 4 |
| `interpret` | **Deferred** — Plan 2 | depends on macro rows from sub-spec 2 |
| Sample-accurate audio-clock-driven tick | **Deferred** — sub-spec 10 | software-timed for Plan 1 |

Deferrals are deliberate scope-shaves to keep Plan 1 producing working, tagged software. Each deferred item names the sub-spec / plan that picks it up.

## Open questions resolved for this plan

- **Command queue capacity:** 1024 entries. If an enqueue returns false, the UI logs "engine command queue overflow" and drops the command; UI parameter sliders use last-wins semantics so a drop just means a skipped intermediate value, not a stuck state.
- **Tick rate granularity:** Ticks are phrase-steps, not sub-step divisions. 16 steps × 4/4 means every tick = 1/16 note. Finer subdivisions (ratchets, micro-timing) are handled by blocks at per-tick resolution, not by tick-rate changes.
- **Command-queue producer vocabulary:** UI is a single producer (serialised through `MainActor`); the engine tick is the single consumer. No multi-producer scenario in this plan.
- **How does `note-generator` state persist across ticks?** It holds a private tick counter; reset behaviour matches the spec's default stateful-block policy (`reset-per-ref-start`) — not implemented yet (no phrase-refs in this plan). For this plan, state simply persists for the lifetime of the block instance.
