# Core Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a runnable pipeline engine that ticks at a user-configurable BPM, executes a small DAG of typed blocks per tick, emits MIDI on a virtual CoreMIDI destination, and receives parameter updates from the UI thread through a lock-free command queue. Verified end-to-end via XCTest: the test wires `note-generator → midi-out`, drives the engine for N ticks, and asserts that M expected MIDI events arrive on a virtual input.

**Architecture:** One Swift module (`Engine`) that owns the executor, block registry, typed streams, and command queue. Blocks conform to a narrow protocol (`tick(context:) -> OutputBundle`) — a block reads typed streams from the `TickContext` and writes one or more typed streams as its outputs. The executor holds a topologically-sorted block list and runs them in order per tick. The `TickClock` fires at `60 / BPM / stepsPerBar * 4` seconds using a serial dispatch queue (MVP — replaced by an audio-clock-driven source in the audio-engine plan). Parameter changes from the UI go through a lock-free single-producer-single-consumer `CommandQueue` drained at the top of each tick. No audio engine integration in this plan — the tick clock is software-timed, sample-accurate scheduling lands when the audio-side plan arrives.

**Tech Stack:** Swift 5.9+, Foundation (DispatchQueue, DispatchSourceTimer), CoreMIDI via the existing `MIDIClient`, `os.unfair_lock`-free ring buffer for the command queue, XCTest.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — sub-spec 1 (Core engine). Scope-shave vs. spec: this plan ships tick-loop + registry + streams + command-queue + `note-generator` source + `midi-out` sink. The remaining spec-listed blocks (`clip-reader`, `force-to-scale`, `quantise-to-chord`, `interpret`) are deferred to a follow-up **Plan 2: Core blocks** because (a) `clip-reader` depends on a clip data model that belongs with the phrase/macro plan (spec sub-spec 2), (b) `interpret` reads abstract macro rows that also belong there, and (c) splitting produces working, tagged software at each milestone.

**Why not audio-clock-driven ticks yet:** Audio-engine integration is a separate spec sub-spec (10). Starting with a `DispatchSourceTimer` gives us a testable engine today; swapping the clock source later is a local change because `TickClock` is injected into the executor via a protocol, not hard-coded. The executor itself is clock-agnostic.

**Environment note:** Same Xcode-16 / `DEVELOPER_DIR` discipline as Plan 0. All `xcodebuild` commands prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## File Structure

All paths relative to project root.

```
Sources/
  Engine/
    Block.swift               # Block protocol, BlockID, PortSpec, TickContext
    Stream.swift              # Typed stream value types
    Executor.swift            # DAG executor
    BlockRegistry.swift       # id → factory, type-checks connections
    TickClock.swift           # BPM-driven software tick source
    CommandQueue.swift        # Lock-free SPSC ring buffer
    Blocks/
      NoteGenerator.swift     # Source: emits note-stream
      MidiOut.swift           # Sink: consumes note-stream → MIDIClient
Tests/
  SequencerAITests/
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

## Task 1: Add Engine module + typed streams

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

## Task 2: Block protocol + TickContext

**Scope:** The narrow contract every block satisfies. `Block` gets a `tick(context:)` that reads input streams from the `TickContext`, does its work, and returns its outputs as a `[PortID: Stream]` dict.

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
}
```

**Acceptance:** A trivial test block is defined inside `BlockProtocolTests` that just emits `.scalar(0.5)` on output `"value"`; the test verifies its contract declaration and one `tick` call.

- [ ] Write test for the trivial block
- [ ] Write `Block.swift`
- [ ] Green
- [ ] Commit: `feat(engine): block protocol + TickContext`

---

## Task 3: Executor (topological tick)

**Scope:** The piece that runs a DAG of blocks per tick. Holds `[Block]` in topological order and a `[BlockID: [PortID: (upstream BlockID, upstream PortID)]]` wiring table. Per `tick()`: for each block in order, gather its inputs from the wiring table's already-computed outputs of earlier blocks, call `block.tick(context:)`, stash outputs.

Topological sort is computed once at graph-load time (not every tick). Cycle detection at load-time emits a descriptive error.

**Files:**
- Create: `Sources/Engine/Executor.swift`
- Create: `Tests/SequencerAITests/Engine/ExecutorTests.swift`

**Public API:**

```swift
public final class Executor {
    public init(blocks: [Block], wiring: [BlockID: [PortID: (BlockID, PortID)]]) throws
    public func tick(bpm: Double, now: TimeInterval) -> [BlockID: [PortID: Stream]]

    public enum Error: Swift.Error, Equatable {
        case cycleDetected(path: [BlockID])
        case missingUpstream(blockID: BlockID, portID: PortID)
        case streamKindMismatch(blockID: BlockID, portID: PortID, expected: StreamKind, got: StreamKind)
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

- [ ] Write failing tests (6 cases above)
- [ ] Implement topological sort
- [ ] Implement `tick`
- [ ] Implement cycle / wiring / type-check validation
- [ ] Green
- [ ] Commit: `feat(engine): DAG executor with topological tick`

---

## Task 4: BlockRegistry

**Scope:** String-keyed factory. UI/document code creates a block by its kind identifier (e.g. `"note-generator"`) so blocks can be serialised without type-erasure gymnastics. The registry also reports each kind's `PortSpec`s so the graph editor can type-check wiring before calling the executor.

**Files:**
- Create: `Sources/Engine/BlockRegistry.swift`
- Create: `Tests/SequencerAITests/Engine/BlockRegistryTests.swift`

**Public API:**

```swift
public struct BlockKind: Equatable, Sendable {
    public let id: String                   // "note-generator", "midi-out"
    public let inputs: [PortSpec]
    public let outputs: [PortSpec]
    public let make: (BlockID, [String: Any]) -> Block
}

public final class BlockRegistry {
    public init()
    public func register(_ kind: BlockKind)
    public func kinds() -> [BlockKind]
    public func make(kindID: String, blockID: BlockID, params: [String: Any] = [:]) -> Block?
}
```

**Tests:**

1. Register a test kind, retrieve by `kindID`, make an instance.
2. Unknown `kindID` returns `nil`.
3. `kinds()` reflects every registration.
4. Double-registration of the same `kindID` is an error (test pending the decision: replace vs throw — recommend throw).

- [ ] Tests for the four cases
- [ ] Implement registry
- [ ] Green
- [ ] Commit: `feat(engine): block registry`

---

## Task 5: TickClock (BPM-driven software tick source)

**Scope:** A serial-dispatch-queue-backed timer that fires a tick handler at the interval corresponding to the current BPM and `stepsPerBar`. Default `stepsPerBar = 16`; default time signature 4/4. Tick interval = `60.0 / bpm / stepsPerBar * 4.0` seconds.

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

**Tests:**

1. Start at 240 BPM × 16 steps/bar → interval 62.5ms. Test runs for 500ms; asserts ≥6 and ≤10 ticks arrived (tolerance for DispatchSourceTimer jitter).
2. Stop inside handler — no further ticks after `stop()` returns.
3. Change BPM while running — observed interval changes on the next tick.
4. Tick index starts at 0 and increments monotonically.

- [ ] Tests (accept jitter tolerances explicitly — don't over-assert timing)
- [ ] Implementation using `DispatchSource.makeTimerSource`
- [ ] Green (be patient with CI flakiness — these tests time out after 2s each)
- [ ] Commit: `feat(engine): BPM-driven tick clock`

---

## Task 6: CommandQueue (UI → engine SPSC ring buffer)

**Scope:** A fixed-capacity, lock-free single-producer-single-consumer ring buffer for parameter updates from the UI thread to the engine thread. No allocations on the hot path. The engine drains the queue at the top of each `tick`.

**Files:**
- Create: `Sources/Engine/CommandQueue.swift`
- Create: `Tests/SequencerAITests/Engine/CommandQueueTests.swift`

**Design choice:** Use a fixed-size `UnsafeMutableBufferPointer<Command>` with atomic head/tail indices from `Atomics` (Swift's atomics package) — or, if adding a package dependency is undesirable, two `OSAtomic`-backed `Int` via `UnsafeMutablePointer`. Recommend `Atomics` for code clarity; add as a package dep in `project.yml`.

**Command payload:**

```swift
public enum Command: Sendable {
    case setParam(blockID: BlockID, paramKey: String, value: ParamValue)
    case setBPM(Double)
}

public enum ParamValue: Equatable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
}
```

**Public API:**

```swift
public final class CommandQueue {
    public init(capacity: Int)            // capacity = power of 2 recommended
    public func enqueue(_ command: Command) -> Bool    // false = full, drop
    public func drainAll() -> [Command]
}
```

**Tests:**

1. Enqueue N < capacity → drain returns N in FIFO order.
2. Enqueue past capacity → returns false; drain doesn't include dropped entries.
3. Enqueue from one dispatch queue, drain from another → no crashes, all commands appear.
4. Stress: 10K enqueue/drain cycles with concurrent producers and a consumer.

- [ ] Tests (include the concurrency test; use `XCTestExpectation` + `DispatchGroup`)
- [ ] Implement using `Atomics`
- [ ] Green
- [ ] Commit: `feat(engine): SPSC lock-free command queue`

---

## Task 7: NoteGenerator source block

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

## Task 8: MidiOut sink block

**Scope:** A block with one input (`notes: .notes`, required) and no outputs. Consumes `Stream.notes(...)` each tick and emits MIDI to a configured `MIDIEndpoint` via `MIDIClient.send(...)`. The `MIDIClient` comes from Plan 0.

Configurable via params: `channel: UInt8` (default 0, i.e. MIDI ch 1), `noteOffsetTicks: Int` (default 0 — schedule note-off at `length + offset` ticks in the future).

**Files:**
- Create: `Sources/Engine/Blocks/MidiOut.swift`
- Create: `Tests/SequencerAITests/Engine/MidiOutTests.swift`

**API on MIDIClient:** this task may need to add a `send(_ packet: MIDIPacket, to: MIDIEndpoint)` helper if Plan 0's `MIDIClient` doesn't expose one already. Check `Sources/MIDI/MIDIClient.swift` first; if it's there, use it; if not, add it as a minimum on top of the existing client (separate commit before the MidiOut block commit).

**Tests:**

1. Input stream carries 1 note → `MIDIClient` receives 1 note-on + 1 scheduled note-off.
2. Input stream carries 0 notes → nothing sent.
3. Input stream carries 3 notes (chord) → 3 note-on + 3 note-off.
4. Block registers in registry under `"midi-out"`.

Use the virtual endpoint / virtual input pattern from Plan 0's `MIDIClientTests` — create a virtual destination, subscribe, assert packets.

- [ ] Tests (creates virtual MIDI endpoint, asserts CoreMIDI callback fires)
- [ ] Implementation (may need a `MIDIClient.send` helper — commit that first if missing)
- [ ] Green
- [ ] Commit: `feat(engine): midi-out sink block`

---

## Task 9: End-to-end integration

**Scope:** Prove the whole stack works together. Wire `note-generator → midi-out`, drive the executor from the `TickClock`, observe MIDI events on a virtual input, send a command-queue `setBPM` mid-run and verify the tick rate changes.

**Files:**
- Create: `Tests/SequencerAITests/Engine/EngineIntegrationTests.swift`

**Scenario:**

```swift
func test_engine_emits_expected_midi_for_N_ticks() {
    let midiClient = try MIDIClient()
    let dest = try midiClient.createVirtualInput("test-in")
    let src = try midiClient.createVirtualOutput("test-out")
    // Connect dest's callback to record received packets.

    let gen = NoteGenerator(id: "gen", params: […])
    let out = MidiOut(id: "out", params: [.endpoint: dest])
    let executor = try Executor(
        blocks: [gen, out],
        wiring: ["out": ["notes": ("gen", "notes")]]
    )

    let clock = TickClock(stepsPerBar: 16)
    clock.bpm = 480  // fast — 16 ticks in 500ms
    let received = RecorderHarness()
    clock.start { idx, now in
        let outputs = executor.tick(bpm: clock.bpm, now: now)
        // executor writes to midi-out inside its tick; no further routing needed.
    }
    wait 500ms; clock.stop()
    XCTAssertGreaterThanOrEqual(received.noteOnCount, 15)
}
```

A second test verifies a `setBPM` command fed through the `CommandQueue` changes the clock rate.

- [ ] Test scenario 1: 16 notes emitted in 500ms at 480 BPM × 16
- [ ] Test scenario 2: BPM change mid-run
- [ ] Green
- [ ] Commit: `test(engine): end-to-end note-generator → midi-out integration`

---

## Task 10: Wire Engine into the app shell

**Scope:** Expose the engine to the SwiftUI app: a single `EngineController` `@Observable` (macOS 14+) that owns an `Executor`, a `TickClock`, a `CommandQueue`, and a `BlockRegistry`. Bound to Play/Stop buttons in `TransportBar.swift` (Plan 0 placeholder). No graph editor yet — the shell creates a hard-coded `note-gen → midi-out` pipeline for smoke-testing.

This surfaces the engine in the running app. The user can hit Play and hear MIDI on a routed destination.

**Files:**
- Create: `Sources/Engine/EngineController.swift`
- Modify: `Sources/UI/TransportBar.swift` (wire Play/Stop to `EngineController`)
- Modify: `Sources/App/SequencerAIApp.swift` (construct the controller; pass down via environment)
- Create: `Tests/SequencerAITests/Engine/EngineControllerTests.swift` (unit: start/stop toggles `isRunning`)

- [ ] EngineControllerTests — start/stop state transitions
- [ ] EngineController implementation
- [ ] TransportBar wiring
- [ ] App entry wiring
- [ ] Manual smoke test: hit Play, observe MIDI on a DAW or MIDI monitor app; note in commit message
- [ ] Green `xcodebuild test`
- [ ] Commit: `feat(engine): wire engine into app shell + transport`

---

## Task 11: Wiki update

**Scope:** Add `wiki/pages/engine-architecture.md` describing the block protocol, stream types, executor contract, and tick-clock approach. Update `wiki/pages/project-layout.md` to reflect the new `Engine/` module and its position in the dependency graph.

**Files:**
- Create: `wiki/pages/engine-architecture.md`
- Modify: `wiki/pages/project-layout.md`

Dispatched via the `wiki-maintainer` agent after the main code lands — this task is the execute-plan step-7 equivalent for this plan.

- [ ] Wiki page covers: block protocol, 6 stream kinds, executor ordering, tick-clock model (and why it's software-timed for now), command-queue contract
- [ ] `project-layout.md` gains the `Engine` module row
- [ ] Commit: `docs(wiki): engine architecture + project-layout update`

---

## Task 12: Tag + mark completed

- [ ] Replace every `- [ ]` in this file with `- [x]` for steps actually completed
- [ ] Add `Status: ✅ Completed YYYY-MM-DD. Tag v0.0.2-core-engine at <SHA>.` after `Parent spec`
- [ ] Commit: `docs(plan): mark 1-core-engine completed`
- [ ] Tag: `git tag -a v0.0.2-core-engine -m "Core engine complete: tick loop + executor + streams + command queue + note-gen + midi-out + shell wiring"`

---

## Spec coverage check (self-review)

| Spec item (sub-spec 1) | Task |
|---|---|
| Swift tick loop driven from audio clock | **Deferred** — `TickClock` is software-timed; audio-clock source is sub-spec 10's work. Documented in Architecture header. |
| Pipeline DAG executor | Task 3 |
| Block registry | Task 4 |
| Typed streams | Task 1 |
| Lock-free UI↔render command queue | Task 6 |
| `note-gen` | Task 7 |
| `midi-out` | Task 8 |
| `clip-reader` | **Deferred** — Plan 2 (core blocks), depends on clip data model from sub-spec 2 |
| `force-to-scale` | **Deferred** — Plan 2 (pure transform, can land with the block library) |
| `quantise-to-chord` | **Deferred** — Plan 2 (depends on chord-context plumbing from sub-spec 4) |
| `interpret` | **Deferred** — Plan 2 (depends on macro rows from sub-spec 2) |

Deferrals are deliberate scope-shaves to keep Plan 1 producing working, tagged software. The deferred blocks become Plan 2 or later and each gets its own TDD sub-plan.

## Open questions resolved for this plan

- **Command queue capacity:** 1024 entries. If an enqueue returns false, the UI logs "engine command queue overflow" and drops the command; UI parameter sliders use last-wins semantics so a drop just means a skipped intermediate value, not a stuck state.
- **Tick rate granularity:** Ticks are phrase-steps, not sub-step divisions. 16 steps × 4/4 means every tick = 1/16 note. Finer subdivisions (ratchets, micro-timing) are handled by blocks at per-tick resolution, not by tick-rate changes.
- **Command-queue producer vocabulary:** UI is a single producer (serialised through `MainActor`); the engine tick is the single consumer. No multi-producer scenario in this plan.
- **How does `note-generator` state persist across ticks?** It holds a private tick counter; reset behaviour matches the spec's default stateful-block policy (`reset-per-ref-start`) — not implemented yet (no phrase-refs in this plan). For this plan, state simply persists for the lifetime of the block instance.
