import AVFoundation
import XCTest
@testable import SequencerAI

/// PHASE 0 ENGINE-WIRING test (builder work product — NOT a frozen rail).
///
/// The frozen Phase-0 rail (`Tests/.../EventRecordingRoundTripTests.swift`)
/// asserts the recorder/replay CODEC round-trips in isolation, but never drives
/// `EngineController`. The SPEC, however, mandates the wiring explicitly:
///
///   Phase 0 call sites: "`EngineController.prepareTick` where `GeneratedNote` →
///   `noteEvent` (~:2018-2064); a recorder sink; a replay source."
///   Executable gate: "record→replay round-trips ... the headless capture rig
///   can replay a recording deterministically."
///
/// This test closes that gap: it drives the REAL `prepareTick`/dispatch path on
/// a live `EngineController` and proves
///   (1) the recorder sink captures the realized note stream as the engine
///       produces it (record), and
///   (2) a replay source feeds that recording back through the SAME dispatch
///       path, deterministically reproducing the recorded stream (replay).
///
/// Deterministic: a clip-backed project (no RNG), a `CountingAudioSink`, manual
/// `processTick` pumping — no `AVAudioEngine`, no audio device.
final class EventRecordingEngineWiringTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
    }

    override func tearDown() {
        MainAudioGraph.simulateAudioInputConnectionForTesting = false
        super.tearDown()
    }

    /// Pump steps 0..<count through the engine, returning the per-step events the
    /// sink actually played (the realized dispatch stream).
    @discardableResult
    private func pump(_ controller: EngineController, sink: CountingAudioSink, steps: Int) -> [[NoteEvent]] {
        sink.resetPlayedEvents()
        for step in 0..<steps {
            controller.processTick(tickIndex: UInt64(step), now: Double(step))
        }
        return sink.playedEvents
    }

    // MARK: - Record: the sink captures the realized engine stream

    func test_prepareTick_recordsRealizedStreamThroughEngine() throws {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true, true, true, true])
        controller.apply(documentModel: project)

        let recorder = controller.enableEventRecording()
        XCTAssertNotNil(controller.activeEventRecorder, "enabling recording must install a recorder sink")

        controller.start()
        let played = pump(controller, sink: sink, steps: 4)
        controller.stop()

        // The realized dispatch stream is non-empty (the clip fires every step).
        let totalPlayed = played.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(totalPlayed, 0, "fixture must realize a non-empty note stream through the engine")

        // The recorder must have captured the realized stream as the engine
        // produced it — NOT be empty (the pre-fix state, where no sink exists in
        // prepareTick — the prosecuted defect).
        let recorded = recorder.recordedEvents
        XCTAssertFalse(
            recorded.isEmpty,
            "the recorder sink must capture the realized note stream produced in prepareTick — " +
            "an empty recording means no recorder is wired into the engine (the prosecuted defect)"
        )

        // Every recorded event must belong to this track's generator block and
        // carry the realized pitch the dispatch path played.
        let blockID = EngineController.generatorBlockID(for: trackID)
        XCTAssertTrue(recorded.allSatisfy { $0.blockID == blockID }, "recorded events must key on the track's generator block id")
        XCTAssertTrue(recorded.contains { $0.pitch == 60 }, "recorder must capture the realized clip pitch")

        // The recorder must capture AT LEAST every note the sink played (the
        // engine look-ahead double-pump may legitimately have pre-recorded one
        // further step than the pump dispatched — the recording is a superset of
        // the dispatched stream, never a subset).
        let playedNotes = played.flatMap { $0 }.count
        XCTAssertGreaterThanOrEqual(
            recorded.count, playedNotes,
            "the recorder must capture every realized note the dispatch path played"
        )
    }

    // MARK: - Replay: a recording feeds the SAME dispatch path, deterministically

    func test_replaySource_feedsSameDispatchPath_isDeterministic() throws {
        // 1) Record a live run.
        let recSink = CountingAudioSink()
        let recController = EngineController(client: nil, endpoint: nil, audioOutput: recSink)
        let (project, _, _) = makeLiveStoreProject(clipPitch: 64, stepPattern: [true, false, true, true])
        recController.apply(documentModel: project)
        let recorder = recController.enableEventRecording()
        recController.start()
        pump(recController, sink: recSink, steps: 4)
        recController.stop()

        let recordedNDJSON = recorder.serializedNDJSON()
        XCTAssertFalse(recordedNDJSON.isEmpty, "a live run must produce a non-empty recording")
        let originalEvents = recorder.recordedEvents

        // 2) Replay that recording through a FRESH engine driving the SAME
        //    dispatch path, while recording the replay. The replay must drive the
        //    executor from the recording (not re-generate live), so RE-recording
        //    the replayed run reproduces the SAME realized stream the recording
        //    held for the pumped steps — "the headless capture rig can replay a
        //    recording deterministically."
        let replaySink = CountingAudioSink()
        let replayController = EngineController(client: nil, endpoint: nil, audioOutput: replaySink)
        replayController.apply(documentModel: project)
        replayController.beginEventReplay(EventReplaySource(ndjson: recordedNDJSON))
        let replayRecorder = replayController.enableEventRecording()
        replayController.start()
        let replayPlayed = pump(replayController, sink: replaySink, steps: 4)
        replayController.stop()

        // The replay must have actually dispatched notes (the replay source fed
        // the dispatch path) — not silence.
        let replayedNotes = replayPlayed.flatMap { $0 }
        XCTAssertFalse(replayedNotes.isEmpty, "replay must feed notes into the dispatch path (not silence)")

        // The replay drove the SAME dispatch path from the recording, so what it
        // re-recorded must equal the ORIGINAL recording for every step the
        // recording covers — the realized stream is reproduced exactly. Compared
        // as an order-independent multiset (cross-block dictionary dispatch order
        // is not part of the recorded contract) over `RealizedEvent`s, which carry
        // block/step/pitch/velocity/length/gate/voiceTag.
        let replayedEvents = replayRecorder.recordedEvents
        let recordedSteps = Set(originalEvents.map(\.step))
        XCTAssertEqual(
            multiset(replayedEvents.filter { recordedSteps.contains($0.step) }),
            multiset(originalEvents.filter { recordedSteps.contains($0.step) }),
            "replay must reproduce the recorded realized stream through the same dispatch path " +
            "(re-recording the replay equals the original recording, per (block, step))"
        )

        // Determinism: replaying the SAME recording again yields the identical
        // re-recorded realized stream.
        let replaySink2 = CountingAudioSink()
        let replayController2 = EngineController(client: nil, endpoint: nil, audioOutput: replaySink2)
        replayController2.apply(documentModel: project)
        replayController2.beginEventReplay(EventReplaySource(ndjson: recordedNDJSON))
        let replayRecorder2 = replayController2.enableEventRecording()
        replayController2.start()
        pump(replayController2, sink: replaySink2, steps: 4)
        replayController2.stop()

        XCTAssertEqual(
            multiset(replayRecorder2.recordedEvents),
            multiset(replayedEvents),
            "replaying the same recording must be deterministic — identical re-recorded realized stream"
        )
    }

    /// Order-independent count of each distinct realized event (a multiset), so
    /// equality ignores cross-block dictionary dispatch ordering.
    private func multiset(_ events: [RealizedEvent]) -> [RealizedEvent: Int] {
        var counts: [RealizedEvent: Int] = [:]
        for event in events { counts[event, default: 0] += 1 }
        return counts
    }
}
