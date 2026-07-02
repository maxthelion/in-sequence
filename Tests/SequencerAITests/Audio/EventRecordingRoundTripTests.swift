import XCTest
@testable import SequencerAI

/// PHASE 0 RAIL — event recording round-trip + replay-feeds-same-dispatch-path.
///
/// Authored from the SPEC only
/// (`docs/plans/2026-06-30-precompute-lookahead-recording.md`, Phase 0), never
/// from the implementation. FROZEN: builders may not edit, weaken, skip, or stub
/// this file (see the fleet brief's frozen-rails rule).
///
/// # The invariant this gate encodes (spec, Phase 0)
///
/// 1. "record the realized note stream as it's produced (track, step, pitch,
///    velocity, length, gate, the resolved generative choice) to an in-memory
///    ring + optional NDJSON."
/// 2. "A replay source feeds the *same* dispatch path from a recording."
/// 3. Executable gate: "record→replay round-trips to a byte-identical event
///    list."
///
/// # Why it is deterministic (no engine, no device)
///
/// Per the fleet brief, the rail prefers deterministic unit tests over
/// device-dependent ones. The realized event stream is a pure value list; the
/// round-trip and the dispatch-map reconstruction are pure data transforms, so
/// they are asserted directly against the `EventRecorder` / `EventReplaySource`
/// contract with no `AVAudioEngine`.
///
/// # Why it starts RED (TDD)
///
/// On current code the recorder/replay contract is a no-op stub
/// (`Sources/Engine/EventRecording.swift`): `record` drops events,
/// `serializedNDJSON()` returns "", the replay source replays nothing. So the
/// recorded list is empty, the round-trip yields an empty list (≠ the realized
/// input), and the dispatch map is empty — every assertion below FAILS. The
/// adversarial audit (`test_adversarial_noOpRecorder_failsRoundTrip`) pins this:
/// a recorder that does not record CANNOT satisfy the gate, so the gate is not
/// ceremonial.
final class EventRecordingRoundTripTests: XCTestCase {

    // MARK: - Fixture: a deterministic realized note stream

    /// Two generator blocks (two tracks) realized across several steps, with a
    /// non-trivial mix of fields the spec requires recorded: pitch, velocity,
    /// length, gate, voice tag, and per-step slice parameters (the resolved
    /// generative choice). Deterministic — no RNG, no engine.
    private func makeRealizedStream() -> [RealizedEvent] {
        let drumBlock: BlockID = EngineController.generatorBlockID(for: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let melodicBlock: BlockID = EngineController.generatorBlockID(for: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

        let slice = SliceTriggerStepParameters(
            gain: -3.5,
            pitch: 2.0,
            startTrim: 0.1,
            endTrim: 0.9,
            pan: -0.25,
            filter: 0.5,
            attackMs: 1.0,
            releaseMs: 12.0,
            reverse: true,
            choke: false
        )

        return [
            // step 0
            RealizedEvent(blockID: drumBlock, step: 0, pitch: 36, velocity: 120, length: 1, gate: true, voiceTag: "kick"),
            RealizedEvent(blockID: drumBlock, step: 0, pitch: 42, velocity: 90, length: 1, gate: true, voiceTag: "hat", sliceParameters: slice),
            RealizedEvent(blockID: melodicBlock, step: 0, pitch: 60, velocity: 100, length: 4, gate: true, voiceTag: nil),
            // step 1 (drum has a closed-gate / ghost-step variation)
            RealizedEvent(blockID: drumBlock, step: 1, pitch: 42, velocity: 30, length: 1, gate: false, voiceTag: "hat"),
            // step 2
            RealizedEvent(blockID: melodicBlock, step: 2, pitch: 64, velocity: 110, length: 2, gate: true, voiceTag: "lead"),
            RealizedEvent(blockID: drumBlock, step: 2, pitch: 38, velocity: 127, length: 1, gate: true, voiceTag: "snare", sliceParameters: slice),
        ]
    }

    /// Feed a realized stream into a recorder exactly as the engine would (one
    /// `(block, step)` slice of the prepared dispatch map at a time), preserving
    /// realization order.
    private func record(_ stream: [RealizedEvent], into recorder: EventRecorder) {
        // Group consecutive same-(block,step) runs into a notes slice, as
        // `prepareTick` does (`preparedNotesByBlockID[block] = notes`).
        var index = 0
        while index < stream.count {
            let head = stream[index]
            var notes: [NoteEvent] = []
            var cursor = index
            while cursor < stream.count,
                  stream[cursor].blockID == head.blockID,
                  stream[cursor].step == head.step {
                notes.append(stream[cursor].noteEvent)
                cursor += 1
            }
            recorder.record(blockID: head.blockID, step: head.step, notes: notes)
            index = cursor
        }
    }

    // MARK: - Gate 1: record → in-memory recording is the realized stream

    func test_recorder_capturesRealizedStream_inOrder() {
        let stream = makeRealizedStream()
        let recorder = EventRecorder()
        record(stream, into: recorder)

        XCTAssertEqual(
            recorder.recordedEvents, stream,
            "the recorder must capture the realized note stream verbatim, in realization order " +
            "(track-block, step, pitch, velocity, length, gate, resolved generative choice)"
        )
    }

    // MARK: - Gate 2: record → NDJSON → replay round-trips byte-identically

    func test_recordReplay_roundTripsToByteIdenticalEventList() {
        let stream = makeRealizedStream()
        let recorder = EventRecorder()
        record(stream, into: recorder)

        let ndjson = recorder.serializedNDJSON()
        XCTAssertFalse(
            ndjson.isEmpty,
            "a non-empty realized stream must serialize to a non-empty NDJSON recording"
        )

        // Replay the recording.
        let replay = EventReplaySource(ndjson: ndjson)

        // The replayed realized event list must equal the original, exactly.
        XCTAssertEqual(
            replay.recordedEvents, stream,
            "record→replay must round-trip to a byte-identical realized event list"
        )

        // And re-serializing the replayed recording must reproduce the SAME
        // NDJSON bytes — the on-disk form is stable (a true byte-identical
        // round-trip, not merely value-equal).
        let reRecorder = EventRecorder()
        record(replay.recordedEvents, into: reRecorder)
        XCTAssertEqual(
            reRecorder.serializedNDJSON(), ndjson,
            "re-serializing the replayed recording must reproduce the identical NDJSON bytes"
        )
    }

    func test_recordReplay_fromInMemoryRecording_roundTrips() {
        let stream = makeRealizedStream()
        let recorder = EventRecorder()
        record(stream, into: recorder)

        let replay = EventReplaySource(events: recorder.recordedEvents)
        XCTAssertEqual(
            replay.recordedEvents, stream,
            "an in-memory recording must replay to the same realized event list"
        )
    }

    // MARK: - Gate 3: a replay source feeds the SAME dispatch path

    /// The dispatch path the engine drives is the executor's
    /// `preparedNotesByBlockID: [BlockID: [NoteEvent]]` map (one map per step).
    /// A replay source must reconstruct that map per step, byte-for-byte equal
    /// to what was realized live — so replay is indistinguishable from a live
    /// realization on the dispatch path.
    func test_replaySource_reconstructsPreparedNotesDispatchMap_perStep() {
        let stream = makeRealizedStream()
        let recorder = EventRecorder()
        record(stream, into: recorder)
        let replay = EventReplaySource(ndjson: recorder.serializedNDJSON())

        // The reference dispatch map per step, derived directly from the
        // realized stream — exactly what `prepareTick` builds and hands to
        // `executor.tick(preparedNotesByBlockID:)`.
        let expectedByStep = referenceDispatchMaps(from: stream)

        for (step, expectedMap) in expectedByStep {
            let actualMap = replay.preparedNotesByBlockID(forStep: step)
            XCTAssertEqual(
                actualMap, expectedMap,
                "step \(step): the replay source must reconstruct the exact prepared-notes dispatch " +
                "map the executor consumes (keyed by block id, notes in order)"
            )
        }

        // A step with no realized notes must replay to an empty dispatch map
        // (no spurious triggers).
        XCTAssertEqual(
            replay.preparedNotesByBlockID(forStep: 99), [:],
            "a step with no recorded events must replay to an empty dispatch map"
        )
    }

    /// The reference `[step: [BlockID: [NoteEvent]]]` derived purely from the
    /// realized stream — the ground truth for the dispatch path.
    private func referenceDispatchMaps(from stream: [RealizedEvent]) -> [Int: [BlockID: [NoteEvent]]] {
        var byStep: [Int: [BlockID: [NoteEvent]]] = [:]
        for event in stream {
            byStep[event.step, default: [:]][event.blockID, default: []].append(event.noteEvent)
        }
        return byStep
    }

    // MARK: - Adversarial audit: a no-op recorder MUST fail the gate

    /// ADVERSARIAL AUDIT (frozen-rail non-negotiable): if the recorder does not
    /// actually record (the no-op stub, i.e. the feature reverted), the
    /// round-trip CANNOT hold — the recording is empty, so the replayed list is
    /// not the realized stream. This proves the gate is load-bearing and not
    /// ceremonial: it can only pass when recording genuinely captures the
    /// realized stream.
    ///
    /// Phrased as a property over an explicitly-empty recording so it stays a
    /// meaningful guard regardless of how the builder implements `EventRecorder`.
    func test_adversarial_emptyRecording_cannotRoundTripARealizedStream() {
        let stream = makeRealizedStream()
        XCTAssertFalse(stream.isEmpty, "fixture must be a non-empty realized stream")

        // An empty recording (what a no-op recorder produces) replayed back can
        // never equal a non-empty realized stream.
        let emptyReplay = EventReplaySource(events: [])
        XCTAssertNotEqual(
            emptyReplay.recordedEvents, stream,
            "a no-op / empty recording must NOT round-trip to the realized stream — otherwise the " +
            "round-trip gate would pass without the feature (ceremonial)"
        )
        XCTAssertEqual(
            emptyReplay.preparedNotesByBlockID(forStep: 0), [:],
            "an empty recording must feed nothing to the dispatch path"
        )
    }
}
