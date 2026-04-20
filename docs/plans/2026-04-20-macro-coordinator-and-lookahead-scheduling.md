# Macro Coordinator + Lookahead Scheduling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the **prepare / dispatch** split in the engine tick loop, with an `EventQueue` sitting between phases; introduce a `MacroCoordinator` that evaluates phrase-layer cells per-step and produces a `LayerSnapshot` in the prepare phase; wire the existing `.mute` phrase layer end-to-end as a walking skeleton so future layers (volume, transpose, intensity, …) slot into a proven pattern. Verified by: `EngineController.processTick` is a two-line dispatcher (`dispatchTick()` then `prepareTick(upcomingStep:now:)`); a new test proves a track whose current step's mute cell resolves to `true` emits zero AU and routed events while other tracks play; `.bars`/`.steps` cell modes on the mute layer are honored (not collapsed to step 0); no regression on existing MIDI/AU/routing tests; full suite green.

**Architecture:**

The render path should be as cheap as possible. Three concerns, put on three sides of the hot-path boundary:

1. **Source cache (AOT, edit-time).** `NoteGenerator`'s `NoteProgram` is already the right shape — compute the step-by-step note material when the source changes, then just index into it at tick time. Not touched by this plan.
2. **Coordinator (prepare-phase, cheap).** Between steps, the `MacroCoordinator` reads the current phrase's cells for each active layer at the upcoming step and emits a plain-struct `LayerSnapshot`. No random draws, no algorithm evaluation — just `resolvedValue(for:trackID:stepIndex:)` reads and switch statements.
3. **Event queue (between prepare and dispatch).** Prepare runs the existing executor + router machinery, applies the snapshot (mute filter in this plan), and enqueues `ScheduledEvent`s. Dispatch drains the queue and fires. Dispatch is constant-cost: drain an array, switch on payload kind, call sink.

The prepare/dispatch pair runs inside one `TickClock` callback for this plan — `dispatchTick()` drains events produced by the previous callback's prepare, then `prepareTick(upcomingStep: tickIndex + 1, now:)` populates the queue for the next callback. This gets the *shape* right without committing to dual-timer offsets or render-thread dispatch yet. Both unlocks become swap-in follow-ups: the queue contract doesn't change when dispatch moves to the audio render thread, only the consumer does.

Scope for the coordinator's first outing is intentionally narrow: **only the `.mute` layer.** Mute is a boolean, the simplest layer to wire, and exercises the full chain (phrase cell → coordinator → snapshot → apply → dispatch filter → tests). Volume, transpose, intensity, and friends are each a follow-up plan of the same shape: add a field to `LayerSnapshot`, add a case to the coordinator's evaluation, add an application point in prepare. Three such follow-ups should clarify what's reusable; don't extract a `PhraseLayerBlock` abstraction before that.

**Separation of concerns — what the program holds vs what the event holds.** The AOT `NoteProgram` already on `NoteGenerator` is the **what-notes** cache: per-step arrays of `ProgrammedNote` (so chords, drum stacks, and piano-roll content all flow through the existing `[[ProgrammedNote]]` shape without special handling by this plan). `ScheduledEvent.scheduledHostTime` is the **when** — set to `now` in this plan but present deliberately so future timing modulations (swing, humanize, groove templates, live push/pull) drop in as "prepare computes a per-event time offset, dispatch / sink honors it." Don't conflate the two: timing modulation does not touch `NoteProgram`.

**MidiOut migration is deliberately out of scope.** `MidiOut` continues to send via `MIDIClient.send` during its block `tick`, which now runs inside `prepareTick`. That means MIDI events still fire during prepare, not dispatch — correct for the current (non-realtime) threading model, and a one-plan refactor away from living in the queue alongside AU and routed events. Migrating `MidiOut` into the queue is a follow-up.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` §"Platform and stack" (*"Pipeline DAG executor runs on a scheduling queue driven by the audio render clock for sample-accurate timing"*) and §"The macro coordinator as information substrate" (*"Every block receives the macro coordinator's tick … clock counters … current macro-row values"*). No new design — implements what the spec already names.
**Status:** [COMPLETED 2026-04-20]

**Depends on:** Current `main` after:
- `v0.0.12-document-as-project-refactor`
- `60fa69b` (`refactor(cleanup): delete legacy destination bridges`)

This plan assumes the post-refactor names already in the tree: `Project`, `SeqAIDocument.project`, and the current phrase-layer schema with `PhraseLayerTarget.mute` already present.

**Deliberately deferred:**

- **Dual-timer offset between prepare and dispatch.** Prepare and dispatch run inside one TickClock callback here. A follow-up moves prepare earlier (or onto its own schedule) so queue latency absorbs prepare-phase variance. The queue contract stays the same.
- **Sample-accurate render-thread dispatch.** `TickClock` stays `DispatchSourceTimer`-based; dispatch stays on the timer queue. When AVAudioEngine lands, dispatch migrates to a render callback drain — the `EventQueue` API is unchanged, only the consumer is.
- **`MidiOut` migration into the queue.** MIDI still sends via direct `MIDIClient.send` inside block tick (running in prepare phase). Follow-up plan: refactor `MidiOut` to emit `ScheduledEvent.midiNote` payloads and move the actual CoreMIDI send into `dispatchTick`.
- **Lock-free `EventQueue`.** A simple `NSLock`-guarded array is fine for a timer-driven dispatch phase. Lock-free becomes necessary once dispatch is on the render thread.
- **Wiring additional layers** (volume, transpose, intensity, density, tension, register, variance, brightness, fill-flag, swing, bpm). Each is a small follow-up: add field to `LayerSnapshot`, evaluate in coordinator, apply in prepare. Do them one at a time; don't batch.
- **Generator re-seeding on phrase or pattern change.** The AOT `NoteProgram` compile path is unchanged. `EngineController.apply(documentModel:)` still drives re-compilation. Explicit re-roll on phrase boundary is a separate plan.
- **Per-pattern-slot `NoteProgram` cache.** Today one program is compiled per track from the step-0 pattern slot. A follow-up plan expands this to a per-slot cache per track and has the coordinator publish `patternIndex: [UUID: Int]` per step — at which point `.bars` / `.steps` / `.curve` cell modes on the pattern layer start hot-swapping slots mid-phrase (currently silently dead). `LayerSnapshot`'s shape is forward-compatible (fields are additive); this plan does nothing to preclude it.
- **Timing modulations** (swing, humanize, groove-template micro-timing, live push/pull). `ScheduledEvent.scheduledHostTime` is the forward-compatible home — this plan just always sets it to `now`. A follow-up adds a time-offset-producing layer to `LayerSnapshot`, computes per-event offsets in prepare, and teaches MIDI / AU sinks to honor the scheduled time (MIDI via `MIDIPacket.timeStamp` — trivial; AU via `AVAudioTime(hostTime:)` — requires `TrackPlaybackSink.play(...)` signature extension).
- **Per-phrase pipeline rebuild.** The executor still has one pipeline shape per document, reshaped on track/destination change. Per-phrase DAG variation is a separate plan.
- **Coordinator-owned song transport.** The coordinator reads `project.selectedPhraseID`; it does not advance phrases. Song-transport phrase-advance is a separate plan.
- **Clock counters beyond `phraseStep`.** The `LayerSnapshot` carries no `absSongStep` / `phraseIndex` / `barInPhrase` yet — nothing consumes them. Add alongside the first consumer (likely the song-transport plan).

Tag: `v0.0.15-coordinator-scheduling`

---

## File Structure (post-plan)

```
Sources/
  Engine/
    ScheduledEvent.swift                            # NEW — ScheduledEvent struct + Payload enum
    EventQueue.swift                                # NEW — thread-safe FIFO of ScheduledEvent
    MacroCoordinator.swift                          # NEW — per-tick LayerSnapshot producer
    LayerSnapshot.swift                             # NEW — plain struct; initially { mute: [UUID: Bool] }
    EngineController.swift                          # modified — processTick split into prepareTick + dispatchTick
    (unchanged: Block, Stream, Executor, BlockRegistry, TickClock, CommandQueue,
                MIDIRouter, TransportMode, Blocks/*)
Tests/
  SequencerAITests/
    Engine/
      EventQueueTests.swift                         # NEW — enqueue / drain / count / thread-safety
      MacroCoordinatorTests.swift                   # NEW — mute evaluation across cell modes
      EngineControllerMuteTests.swift               # NEW — end-to-end: mute cell → no AU events
      (existing tests unchanged)
```

---

## Task 1: Introduce `ScheduledEvent` and `EventQueue`

**Scope:** New foundation types. `ScheduledEvent` wraps a host time and a small payload enum covering the sink kinds that will migrate into the queue in later tasks. `EventQueue` is a thread-safe FIFO — `NSLock`-guarded array is fine.

**Files:**
- Create: `Sources/Engine/ScheduledEvent.swift`:

```swift
import Foundation

struct ScheduledEvent: Equatable {
    enum Payload: Equatable {
        /// Track-destination AU dispatch. Consumed by `TrackPlaybackSink.play(...)`.
        case trackAU(trackID: UUID, destination: Destination, notes: [NoteEvent], bpm: Double, stepsPerBar: Int)

        /// Routed AU dispatch (route → voicing → track).
        case routedAU(trackID: UUID, destination: Destination, notes: [NoteEvent], bpm: Double, stepsPerBar: Int)

        /// Routed MIDI dispatch (route → midi destination). The router currently
        /// drives `MidiOut` blocks directly for MIDI — this payload exists for the
        /// follow-up plan that migrates `MidiOut` into the queue. Unused in this plan.
        case routedMIDI(destination: Destination, channel: UInt8, notes: [NoteEvent], bpm: Double)

        /// Chord-context broadcast update.
        case chordContextBroadcast(lane: String, chord: Chord)
    }

    let scheduledHostTime: TimeInterval
    let payload: Payload
}
```

- Create: `Sources/Engine/EventQueue.swift`:

```swift
import Foundation

final class EventQueue {
    private var events: [ScheduledEvent] = []
    private let lock = NSLock()

    func enqueue(_ event: ScheduledEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func enqueue(_ newEvents: [ScheduledEvent]) {
        guard !newEvents.isEmpty else { return }
        lock.lock()
        events.append(contentsOf: newEvents)
        lock.unlock()
    }

    func drain() -> [ScheduledEvent] {
        lock.lock()
        defer { lock.unlock() }
        let drained = events
        events.removeAll(keepingCapacity: true)
        return drained
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    var isEmpty: Bool {
        count == 0
    }
}
```

- Create: `Tests/SequencerAITests/Engine/EventQueueTests.swift`:

```swift
import XCTest
@testable import SequencerAI

final class EventQueueTests: XCTestCase {
    func test_enqueue_thenDrain_returnsEventsInFIFOOrder() {
        let queue = EventQueue()
        let chord = Chord(root: 60, quality: .major)
        let a = ScheduledEvent(scheduledHostTime: 1.0, payload: .chordContextBroadcast(lane: "a", chord: chord))
        let b = ScheduledEvent(scheduledHostTime: 2.0, payload: .chordContextBroadcast(lane: "b", chord: chord))
        queue.enqueue(a)
        queue.enqueue(b)
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.drain(), [a, b])
        XCTAssertTrue(queue.isEmpty)
    }

    func test_drain_clearsQueue() {
        let queue = EventQueue()
        let chord = Chord(root: 60, quality: .major)
        queue.enqueue(ScheduledEvent(scheduledHostTime: 0, payload: .chordContextBroadcast(lane: "x", chord: chord)))
        _ = queue.drain()
        XCTAssertTrue(queue.isEmpty)
    }

    func test_concurrentEnqueueAndDrain_doesNotCorrupt() {
        let queue = EventQueue()
        let chord = Chord(root: 60, quality: .major)
        let group = DispatchGroup()
        for i in 0..<100 {
            DispatchQueue.global().async(group: group) {
                queue.enqueue(ScheduledEvent(scheduledHostTime: Double(i), payload: .chordContextBroadcast(lane: "\(i)", chord: chord)))
            }
        }
        group.wait()
        XCTAssertEqual(queue.count, 100)
    }
}
```

(If `Chord(root:quality:)` isn't the current initializer — adjust to whatever the actual `Chord` struct in `Sources/Document/` uses; the test body is representative, not literal.)

**Tests:** New only; no existing behavior touched.

- [x] Create `ScheduledEvent.swift` with the body above
- [x] Create `EventQueue.swift` with the body above
- [x] Create `EventQueueTests.swift` with the three test cases
- [x] `xcodegen generate`
- [x] `xcodebuild -scheme SequencerAI test` — green
- [x] Commit: `feat(engine): introduce ScheduledEvent and EventQueue scaffolding`

---

## Task 2: Introduce `LayerSnapshot` and `MacroCoordinator`

**Scope:** New types. `LayerSnapshot` is a plain value struct — one field (`mute`) in this plan; future plans add fields. `MacroCoordinator` is the evaluator — reads the project, current phrase, upcoming step, produces a snapshot. No DAG involvement, no side effects.

**Files:**
- Create: `Sources/Engine/LayerSnapshot.swift`:

```swift
import Foundation

struct LayerSnapshot: Equatable {
    /// Per-track mute state at the current step. Absent key → not muted.
    var mute: [UUID: Bool]

    static let empty = LayerSnapshot(mute: [:])

    func isMuted(_ trackID: UUID) -> Bool {
        mute[trackID] ?? false
    }
}
```

- Create: `Sources/Engine/MacroCoordinator.swift`:

```swift
import Foundation

final class MacroCoordinator {
    /// Produce a LayerSnapshot for the step that is about to play.
    /// - Parameters:
    ///   - upcomingGlobalStep: global tick index of the step being prepared.
    ///   - project: current project state (tracks, layers, phrases).
    ///   - phraseID: id of the currently playing phrase.
    func snapshot(
        upcomingGlobalStep: UInt64,
        project: Project,
        phraseID: UUID
    ) -> LayerSnapshot {
        guard let phrase = project.phrases.first(where: { $0.id == phraseID }) else {
            return .empty
        }
        let stepInPhrase = Int(upcomingGlobalStep % UInt64(max(1, phrase.stepCount)))

        var mute: [UUID: Bool] = [:]
        if let muteLayer = project.layers.first(where: { $0.target == .mute }) {
            for track in project.tracks {
                switch phrase.resolvedValue(for: muteLayer, trackID: track.id, stepIndex: stepInPhrase) {
                case let .bool(isMuted):
                    if isMuted { mute[track.id] = true }
                case .scalar, .index:
                    // Mute layer always normalizes to .bool via PhraseLayerValueType.boolean.
                    break
                }
            }
        }

        return LayerSnapshot(mute: mute)
    }
}
```

- Create: `Tests/SequencerAITests/Engine/MacroCoordinatorTests.swift`:

```swift
import XCTest
@testable import SequencerAI

final class MacroCoordinatorTests: XCTestCase {
    private func project(withMuteCell cell: PhraseCell, for trackID: UUID) -> (Project, UUID) {
        let track = StepSequenceTrack(id: trackID, name: "A", pitches: [60], stepPattern: [true], velocity: 100, gateLength: 4)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let muteLayer = layers.first(where: { $0.target == .mute })!
        var phrase = PhraseModel.default(tracks: [track], layers: layers)
        phrase.setCell(cell, for: muteLayer.id, trackID: trackID)
        let project = Project(
            version: 1,
            tracks: [track],
            layers: layers,
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, phrase.id)
    }

    func test_inheritDefault_returnsEmptyMuteSnapshot() {
        let trackID = UUID()
        let (project, phraseID) = project(withMuteCell: .inheritDefault, for: trackID)
        let snapshot = MacroCoordinator().snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID)
        XCTAssertFalse(snapshot.isMuted(trackID))
    }

    func test_singleTrue_mutesAtEveryStep() {
        let trackID = UUID()
        let (project, phraseID) = project(withMuteCell: .single(.bool(true)), for: trackID)
        for step in [0, 1, 7, 15, 128] as [UInt64] {
            let snapshot = MacroCoordinator().snapshot(upcomingGlobalStep: step, project: project, phraseID: phraseID)
            XCTAssertTrue(snapshot.isMuted(trackID), "step \(step) should be muted")
        }
    }

    func test_barsCell_switchesMuteByBar() {
        // Phrase default is 8 bars × 16 steps = 128 steps; one bool per bar.
        let trackID = UUID()
        let bars: [PhraseCellValue] = [.bool(false), .bool(true), .bool(false), .bool(true),
                                       .bool(false), .bool(true), .bool(false), .bool(true)]
        let (project, phraseID) = project(withMuteCell: .bars(bars), for: trackID)
        let coordinator = MacroCoordinator()
        XCTAssertFalse(coordinator.snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertTrue(coordinator.snapshot(upcomingGlobalStep: 16, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertFalse(coordinator.snapshot(upcomingGlobalStep: 32, project: project, phraseID: phraseID).isMuted(trackID))
    }

    func test_stepsCell_switchesMutePerStep() {
        let trackID = UUID()
        let steps: [PhraseCellValue] = (0..<128).map { .bool($0 % 2 == 1) }
        let (project, phraseID) = project(withMuteCell: .steps(steps), for: trackID)
        let coordinator = MacroCoordinator()
        XCTAssertFalse(coordinator.snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertTrue(coordinator.snapshot(upcomingGlobalStep: 1, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertFalse(coordinator.snapshot(upcomingGlobalStep: 2, project: project, phraseID: phraseID).isMuted(trackID))
    }

    func test_globalStepWrapsByPhraseLength() {
        let trackID = UUID()
        let (project, phraseID) = project(withMuteCell: .steps((0..<128).map { .bool($0 == 5) }), for: trackID)
        let coordinator = MacroCoordinator()
        XCTAssertTrue(coordinator.snapshot(upcomingGlobalStep: 5, project: project, phraseID: phraseID).isMuted(trackID))
        // Wraps: global step 5 + 128 = 133 → 133 % 128 = 5.
        XCTAssertTrue(coordinator.snapshot(upcomingGlobalStep: 133, project: project, phraseID: phraseID).isMuted(trackID))
    }

    func test_missingPhrase_returnsEmpty() {
        let track = StepSequenceTrack(name: "A", pitches: [60], stepPattern: [true], velocity: 100, gateLength: 4)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let project = Project(
            version: 1,
            tracks: [track],
            layers: layers,
            selectedTrackID: track.id,
            phrases: [.default(tracks: [track])],
            selectedPhraseID: UUID()  // not in phrase list
        )
        let snapshot = MacroCoordinator().snapshot(upcomingGlobalStep: 0, project: project, phraseID: UUID())
        XCTAssertTrue(snapshot.mute.isEmpty)
    }
}
```

**Tests:** Six unit cases covering the mute evaluation paths: inheritDefault, single, bars, steps, wrap-around, missing phrase.

- [x] Create `LayerSnapshot.swift`
- [x] Create `MacroCoordinator.swift`
- [x] Create `MacroCoordinatorTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — green
- [x] Commit: `feat(engine): introduce MacroCoordinator with mute layer evaluation`

---

## Task 3: Split `EngineController.processTick` into `prepareTick` + `dispatchTick`

**Scope:** Introduce the queue + coordinator as `EngineController` properties. Split the current `processTick` body. The new `processTick` is a two-line dispatcher: drain events for step N (populated last callback), then prepare events for step N+1. No behavior change yet — events go through the queue but `MidiOut` keeps sending directly inside executor tick.

**Files:**
- Modify: `Sources/Engine/EngineController.swift`:

Add properties:

```swift
private let eventQueue = EventQueue()
private let coordinator = MacroCoordinator()
private var currentLayerSnapshot = LayerSnapshot.empty
```

Replace the existing `processTick(tickIndex:now:)` body with:

```swift
func processTick(tickIndex: UInt64, now: TimeInterval) {
    dispatchTick()
    prepareTick(upcomingStep: tickIndex &+ 1, now: now)
}
```

Add `prepareTick`:

```swift
private func prepareTick(upcomingStep: UInt64, now: TimeInterval) {
    let (executor, audioRuntimes, audioOutputs, generatorIDs, documentModel) = withStateLock {
        (self.executor, self.audioTrackRuntimes, self.audioOutputsByTrackID, self.generatorIDsByTrackID, self.currentDocumentModel)
    }
    guard let executor else { return }

    currentLayerSnapshot = coordinator.snapshot(
        upcomingGlobalStep: upcomingStep,
        project: documentModel,
        phraseID: documentModel.selectedPhraseID
    )

    let outputs = executor.tick(now: now)
    currentBPM = executor.currentBPM
    transportTickIndex = upcomingStep &- 1   // the step we just finished
    transportPosition = Self.transportString(for: transportTickIndex, stepsPerBar: stepsPerBar)

    let triggeredNoteCount = outputs.values.reduce(0) { partial, ports in
        partial + ports.values.reduce(0) { nested, stream in
            if case let .notes(events) = stream { return nested + events.count }
            return nested
        }
    }
    if triggeredNoteCount > 0 {
        lastNoteTriggerUptime = now
        lastNoteTriggerCount = triggeredNoteCount
    }

    // AU dispatch → queue
    for runtime in audioRuntimes.values where !runtime.mix.isMuted && !currentLayerSnapshot.isMuted(runtime.trackID) {
        guard case let .notes(events)? = outputs[runtime.generatorBlockID]?["notes"],
              audioOutputs[runtime.trackID] != nil
        else { continue }
        eventQueue.enqueue(ScheduledEvent(
            scheduledHostTime: now,
            payload: .trackAU(
                trackID: runtime.trackID,
                destination: runtime.destination,
                notes: Self.shifted(events, by: runtime.pitchOffset),
                bpm: executor.currentBPM,
                stepsPerBar: stepsPerBar
            )
        ))
    }

    // Router → existing flushRoutedEvents (kept inline for now; AU routed
    // events go through the queue via flushRoutedNotes below).
    routeDispatchNow = now
    routedNoteEvents = [:]
    routedChords = []
    routedMIDINotes = [:]
    let trackInputs = documentModel.tracks.compactMap { track -> RouterTickInput? in
        guard !currentLayerSnapshot.isMuted(track.id),
              let generatorID = generatorIDs[track.id],
              case let .notes(events)? = outputs[generatorID]?["notes"]
        else { return nil }
        return RouterTickInput(sourceTrack: track.id, notes: events, chordContext: nil)
    }
    router.tick(trackInputs)
    flushRoutedEvents(bpm: executor.currentBPM)
}
```

Add `dispatchTick`:

```swift
private func dispatchTick() {
    let events = eventQueue.drain()
    let audioOutputs = withStateLock { audioOutputsByTrackID }

    for event in events {
        switch event.payload {
        case let .trackAU(trackID, destination, notes, bpm, stepsPerBar):
            guard let host = audioOutputs[trackID] else { continue }
            host.setDestination(destination)
            host.play(noteEvents: notes, bpm: bpm, stepsPerBar: stepsPerBar)

        case let .routedAU(trackID, destination, notes, bpm, stepsPerBar):
            guard let host = audioOutputs[trackID] else { continue }
            host.setDestination(destination)
            host.play(noteEvents: notes, bpm: bpm, stepsPerBar: stepsPerBar)

        case let .chordContextBroadcast(lane, chord):
            chordContextByLane[lane] = chord

        case .routedMIDI:
            // Unused in this plan; reserved for the MidiOut-migration follow-up.
            break
        }
    }
}
```

Modify `flushConcreteDestination(...)` so the `.auInstrument` branch **enqueues** instead of directly calling `host.play`:

```swift
case .auInstrument:
    guard let track,
          !track.mix.isMuted,
          !currentLayerSnapshot.isMuted(track.id),
          audioOutputsByTrackID[track.id] != nil
    else { return }
    eventQueue.enqueue(ScheduledEvent(
        scheduledHostTime: routeDispatchNow,
        payload: .routedAU(
            trackID: track.id,
            destination: destination,
            notes: Self.shifted(notes, by: pitchOffset),
            bpm: bpm,
            stepsPerBar: stepsPerBar
        )
    ))
```

And the chord-context branch of `flushRoutedEvents`:

```swift
for (destination, chord, lane) in routedChords {
    guard case let .chordContext(broadcastTag) = destination else { continue }
    eventQueue.enqueue(ScheduledEvent(
        scheduledHostTime: routeDispatchNow,
        payload: .chordContextBroadcast(lane: broadcastTag ?? lane ?? "default", chord: chord)
    ))
}
```

(The direct `chordContextByLane[...] = chord` write moves into `dispatchTick`.)

**Bootstrap:** On `start()`, call `prepareTick(upcomingStep: 0, now: ProcessInfo.processInfo.systemUptime)` before starting the clock, so step 0's events are queued before the first dispatch callback fires:

```swift
func start() {
    guard !isRunning, executor != nil else { return }
    let hosts = withStateLock { Array(audioOutputsByTrackID.values) }
    hosts.forEach { $0.startIfNeeded() }
    isRunning = true
    prepareTick(upcomingStep: 0, now: ProcessInfo.processInfo.systemUptime)
    clock.start { [weak self] tickIndex, now in
        self?.processTick(tickIndex: tickIndex, now: now)
    }
}
```

**Subtleties:**
- The router's `flushRoutedNotes` for MIDI destinations still drives `MidiOut` blocks directly — leave that alone. Only AU and chord-context dispatches move through the queue.
- `transportTickIndex` semantics: it used to be "the step we're currently firing." Keep that. After the refactor, at the *start* of a callback, `dispatchTick` fires the step that was prepared by the *previous* callback. So `transportTickIndex` updates in `prepareTick` to `upcomingStep &- 1` (the step whose events are now in the queue, about to dispatch next callback). The very first callback dispatches step 0 (prepared in `start()` bootstrap), which means `transportTickIndex` = 0 before dispatch. Audit any callers of `transportTickIndex` after the refactor — if any need "current step" semantics, they're fine; if any need "next step" the offset needs revisiting.
- The `&+ 1` on `tickIndex` avoids overflow on the absurdly long-running case.

**Tests:** Existing `EngineControllerTests`, `MIDIRouterTests`, `TrackFanOutTests`, `ChordContextSinkTests` should all continue to pass — they exercise behavior, not tick-internal structure.

- [x] Add `eventQueue`, `coordinator`, `currentLayerSnapshot` properties to `EngineController`
- [x] Add `prepareTick(upcomingStep:now:)` with the body above
- [x] Add `dispatchTick(now:)` with the body above
- [x] Replace `processTick(tickIndex:now:)` body with the two-line dispatcher
- [x] Modify `flushConcreteDestination`'s `.auInstrument` branch to enqueue
- [x] Modify `flushRoutedEvents`' chord-context branch to enqueue
- [x] Add the bootstrap `prepareTick(upcomingStep: 0, ...)` call in `start()`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — full existing suite green
- [x] Commit: `refactor(engine): split tick loop into prepareTick + dispatchTick via EventQueue`

---

## Task 4: End-to-end mute test

**Scope:** Prove the walking skeleton: a `.mute` cell resolving `true` at the current step suppresses AU dispatch for that track; other tracks continue. This is the test that validates the coordinator → snapshot → apply → dispatch chain is wired.

**Files:**
- Create: `Tests/SequencerAITests/Engine/EngineControllerMuteTests.swift`:

```swift
import XCTest
@testable import SequencerAI

final class EngineControllerMuteTests: XCTestCase {
    /// Spy TrackPlaybackSink that records every play(...) call without touching audio.
    private final class PlaybackSpy: TrackPlaybackSink {
        var playedCounts: [UUID: Int] = [:]
        var isAvailable: Bool = true
        var displayName: String { "spy" }
        var currentAudioUnit: AVAudioUnit? { nil }
        var availableInstruments: [AudioInstrumentChoice] { [] }
        func setDestination(_ destination: Destination) {}
        func setMix(_ mix: TrackMixSettings) {}
        func prepareIfNeeded() {}
        func startIfNeeded() {}
        func stop() {}
        func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
            // Test attaches trackID via a closure-captured id in the setup; see below.
        }
    }

    func test_muteCellSuppressesAUDispatch() {
        // Build a 2-track project: both target AU; track B's mute cell is .single(.bool(true)).
        let trackA = StepSequenceTrack(
            name: "A",
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: "test.a", stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let trackB = StepSequenceTrack(
            name: "B",
            pitches: [64],
            stepPattern: [true],
            destination: .auInstrument(componentID: "test.b", stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [trackA, trackB])
        let muteLayer = layers.first(where: { $0.target == .mute })!
        var phrase = PhraseModel.default(tracks: [trackA, trackB], layers: layers)
        phrase.setCell(.single(.bool(true)), for: muteLayer.id, trackID: trackB.id)

        let project = Project(
            version: 1,
            tracks: [trackA, trackB],
            layers: layers,
            selectedTrackID: trackA.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        var playCountByTrack: [UUID: Int] = [:]
        let factory: () -> TrackPlaybackSink = {
            RecordingSink { trackID, _, _, _ in
                playCountByTrack[trackID, default: 0] += 1
            }
        }
        let controller = EngineController(client: nil, endpoint: nil, audioOutputFactory: factory)
        controller.apply(documentModel: project)
        controller.start()

        // Drive a few ticks manually — don't rely on TickClock timing.
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<8 {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.125)
        }
        controller.stop()

        XCTAssertGreaterThan(playCountByTrack[trackA.id] ?? 0, 0, "track A should have played")
        XCTAssertEqual(playCountByTrack[trackB.id] ?? 0, 0, "track B is muted; should not have played")
    }
}

/// Test-only playback sink that routes every play(...) call into a reporter closure.
final class RecordingSink: TrackPlaybackSink {
    private let report: (UUID, [NoteEvent], Double, Int) -> Void
    private var boundTrackID: UUID?

    init(report: @escaping (UUID, [NoteEvent], Double, Int) -> Void) {
        self.report = report
    }

    var isAvailable: Bool { true }
    var displayName: String { "recording-sink" }
    var currentAudioUnit: AVAudioUnit? { nil }
    var availableInstruments: [AudioInstrumentChoice] { [] }
    func setDestination(_ destination: Destination) {}
    func setMix(_ mix: TrackMixSettings) {}
    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() {}
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        guard let trackID = boundTrackID else { return }
        report(trackID, noteEvents, bpm, stepsPerBar)
    }
    func bind(trackID: UUID) { self.boundTrackID = trackID }
}
```

The above test is sketch-level — if `TrackPlaybackSink` isn't a protocol, the approach is still: inject a fake sink that records `play(...)` calls per track, drive `processTick` directly, assert the muted track's sink is not called.

If `EngineController`'s `audioOutputFactory` always returns the same sink instance (one sink shared across tracks), adapt the test to distinguish per-track dispatch by spying on `host.setDestination` + `host.play` pairs, inferring track identity from the destination componentID.

**Subtleties:**
- Drive `processTick` directly rather than starting the clock — deterministic and fast.
- `controller.start()` still needs to bootstrap `prepareTick(upcomingStep: 0, ...)`, which this test exercises.
- The `stepPattern: [true]` is a one-step cycle, so every tick fires a note.

- [x] Create `EngineControllerMuteTests.swift` with the sketch above, adapted to actual sink injection
- [x] Verify the test initially FAILS (if mute isn't filtering, track B plays) — sanity check
- [x] `xcodebuild test` — passes once Task 3's mute filter is in place
- [x] Commit: `test(engine): end-to-end mute layer suppresses AU dispatch`

---

## Task 5: Update engine wiki

**Scope:** Bring `wiki/pages/engine-architecture.md` current. Add `wiki/pages/macro-coordinator.md` as the reference doc for the new component and the prepare/dispatch split.

**Files:**
- Modify: `wiki/pages/engine-architecture.md`:
  - Add a "Tick lifecycle" section describing the prepare/dispatch split, the queue, and the coordinator
  - Update the "Core blocks" section to note that chord-context dispatch now routes through the queue
  - Fix stale references: "Plan 1 ships two core blocks" is outdated (ChordContextSink exists); routing layer (MIDIRouter) is unmentioned
  - Replace the `.codex-worktree/...` paths with canonical `Sources/Engine/...` paths
- Create: `wiki/pages/macro-coordinator.md`:

```markdown
---
title: "Macro Coordinator"
category: "architecture"
tags: [engine, coordinator, layers, phrase, snapshot, tick, scheduling]
summary: The per-tick evaluator that reads phrase-layer cells and produces a LayerSnapshot consumed in the prepare phase of the tick loop.
last-modified-by: codex
---

## Role

The `MacroCoordinator` runs in the **prepare phase** of the engine tick loop (see [[engine-architecture]]#tick-lifecycle). Its job: for the step that is about to play, evaluate every active phrase layer's cell for every track, and publish a plain-struct `LayerSnapshot` that downstream apply-points read.

It does not generate notes. It does not own pipeline state. It reads `Project` + a phrase id + a global step index and returns a value.

## What it evaluates

For each active layer, for each track, the coordinator calls `PhraseModel.resolvedValue(for:trackID:stepIndex:)` at the upcoming step and packs the result into a typed field on `LayerSnapshot`:

- `.mute` → `snapshot.mute[trackID]: Bool`

Future layers add fields (`volume`, `transpose`, …); the expansion is additive.

## What it does not do

- Compute notes. Note material is pre-generated (see `NoteGenerator.NoteProgram`); the coordinator only evaluates modulations applied on top.
- Advance the song. `Project.selectedPhraseID` is provided as input.
- Own clock counters beyond step index. Phrase-relative counters will land alongside the first consumer.

## Why a separate component

Three responsibilities kept apart:
- **Source cache** (edit-time): generators produce NoteProgram arrays on edit.
- **Coordinator** (prepare-time): reads cells, produces a snapshot — cheap, no allocation in the hot path.
- **Dispatch** (step-boundary): drains an EventQueue, fires sinks.

The coordinator is the seam that lets phrase layers reach runtime without each generator or sink reading the document directly.

## Related pages

- [[engine-architecture]] — where the coordinator fits in the tick lifecycle
- [[document-model]] — PhraseModel and PhraseLayerDefinition definitions
```

**Tests:** None.

- [x] Edit `engine-architecture.md` per the scope notes
- [x] Create `macro-coordinator.md` with the body above
- [x] Commit: `docs(wiki): document prepare/dispatch split and MacroCoordinator`

---

## Task 6: Verify

**Checks:**
- `xcodebuild -scheme SequencerAI test` — full suite green (new + existing).
- `grep -n 'processTick' Sources/Engine/EngineController.swift` — shows the two-line dispatcher plus the two new private methods.
- `grep -rn 'eventQueue' Sources/Engine/` — usage confined to `EngineController`.
- `grep -rn 'MacroCoordinator' Sources/Engine/` — declared once, used once (in `EngineController`).
- Manual smoke: launch the app with a simple two-track project, play. Confirm audio and MIDI output unchanged from pre-plan. Open the phrase workspace, set the mute cell `.single(.bool(true))` for one track, confirm that track goes silent while the other keeps playing.
- Manual smoke 2: set a `.bars` mute cell (e.g. `[false, true, false, true, false, true, false, true]`) on one track and play — track should mute every other bar.

- [x] All checks pass
- [x] Equivalent focused engine coverage plus launch smoke used in place of direct GUI mute interaction for this session
- [x] Commit: `chore: verify macro-coordinator + prepare/dispatch split`

---

## Task 7: Tag + mark completed

- [x] Replace `- [ ]` with `- [x]` for all completed tasks in this file
- [x] Add `**Status:** [COMPLETED YYYY-MM-DD]` line directly under `**Parent spec:**`
- [x] Commit: `docs(plan): mark macro-coordinator-and-lookahead-scheduling completed`
- [x] Tag: `git tag -a v0.0.15-coordinator-scheduling -m "EngineController tick loop split into prepareTick + dispatchTick via EventQueue; MacroCoordinator introduced and wired for mute layer as walking skeleton"`

---

## Goal-to-task traceability

| Architectural goal | Task |
|---|---|
| `ScheduledEvent` + `EventQueue` types exist | 1 |
| `LayerSnapshot` + `MacroCoordinator` types exist | 2 |
| `EngineController.processTick` is a two-line dispatcher | 3 |
| `prepareTick` populates the queue; `dispatchTick` drains | 3 |
| AU dispatch (direct + routed) flows through the queue | 3 |
| Chord-context broadcast flows through the queue | 3 |
| `.mute` layer suppresses AU dispatch end-to-end | 3, 4 |
| `.bars` / `.steps` / wrap-around honored by coordinator | 2 |
| Existing MIDI / AU / routing behavior unchanged | 3, 6 |
| Engine wiki brought current | 5 |

---

## Open questions

- **Does MIDI dispatch through the queue belong in this plan or a follow-up?** Plan takes the follow-up position: leaving `MidiOut` direct-send keeps scope manageable. If the implementer finds the inconsistency intolerable (AU queued, MIDI not), escalating to include MIDI in this plan is defensible — but expect a 30–50% larger diff and more CoreMIDI test churn.
- **Should `currentLayerSnapshot` be locked?** Currently written in `prepareTick` and read in `flushConcreteDestination` (same callback). Single-threaded within a tick. If a follow-up moves `prepareTick` off the dispatch thread, this needs revisiting.
- **Where does per-track `transportTickIndex` live?** The current single `transportTickIndex` assumes one global step rate. Once tracks with cycle lengths diverge from the global rate have per-track position indicators in the UI, "the step we're on" may need per-track resolution. Not this plan's concern, but the coordinator is the natural place to produce those per-track counters when needed.
- **Generator re-seed on phrase change.** `perStepProbability` / `randomWeighted` / `markov` re-rolls are bound to document apply, not phrase boundaries. A separate plan will introduce explicit re-seed hooks. Worth noting so the implementer doesn't try to retrofit them here.
- **When do we add `phraseStep` / `barInPhrase` / `absSongStep` to the snapshot?** The spec mentions them as coordinator output consumed by blocks via `interpret`. No block reads them today, so they're deferred. First consumer will probably be the song-transport plan (the first thing that cares about "which phrase am I in?").
- **`processTick` public surface.** It's `func processTick(...)` on `EngineController` — currently called only from the clock callback and the test harness. Keeping the signature stable preserves test compatibility. If tests find the two-line version awkward to drive (e.g. they want to observe queue state between prepare and dispatch), expose `prepareTick` / `dispatchTick` as internal instead of private.
- **Mute semantics: source-side or output-side?** Resolved: **source-mute**. Muted tracks are filtered before routing, so downstream routes sourced from the muted track fall silent too. See `wiki/pages/macro-coordinator.md`.
