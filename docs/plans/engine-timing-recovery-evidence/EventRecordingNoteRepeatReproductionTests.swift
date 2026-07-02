import AVFoundation
import XCTest
@testable import SequencerAI

/// VERIFIER reproduction (prosecution claim — NOT a frozen rail).
///
/// Claim under test: "Event recording silently drops note-repeat-masked
/// triggers — replay is not byte-identical to the realized stream when
/// note-repeat is active."
///
/// Mechanism: `EngineController.prepareTick` (EngineController.swift:2277) sets
///   `preparedNotesByBlockID[generatorBlockID] = []`
/// for any track in `activeNoteRepeatTrackIDs`, because the realized note-repeat
/// triggers are produced on the SEPARATE `scheduleActiveNoteRepeatsForCurrentTick`
/// path (EngineController.swift:2129), NOT through `executor.tick`. The recorder
/// (EngineController.swift:2293-2296) records `preparedNotesByBlockID` — i.e. the
/// MASKED (empty) map — so the realized note-repeat triggers that actually SOUND
/// are never recorded. An `EventReplaySource` built from that recording dispatches
/// silence for those steps.
///
/// Spec Phase 0 contract (lines 58-68): "record the realized note stream as it's
/// produced ... a replay is indistinguishable from a live realization."
///
/// Deterministic: a clip-backed project (no RNG), a `CountingAudioSink`, manual
/// `processTick` pumping — no `AVAudioEngine`, no audio device.
final class EventRecordingNoteRepeatReproductionTests: XCTestCase {

    /// A single-track clip project whose track has a note-repeat interval and an
    /// AU-instrument destination (so repeated triggers SOUND through the sink).
    private func makeNoteRepeatProject(
        interval: NoteRepeatInterval
    ) -> (Project, UUID) {
        let trackID = UUID(uuidString: "51515151-5151-5151-5151-515151515151")!
        let clipID = UUID(uuidString: "61616161-6161-6161-6161-616161616161")!
        var track = StepSequenceTrack(
            id: trackID,
            name: "Repeat Clip",
            pitches: [48],
            stepPattern: [false],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 70,
            gateLength: 1
        )
        track.noteRepeatInterval = interval
        let clip = ClipPoolEntry(
            id: clipID,
            name: "Repeat Source",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                        fill: nil
                    )
                ]
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip]
        )
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, trackID)
    }

    /// With note-repeat engaged, the engine SOUNDS repeated triggers (via the
    /// separate note-repeat scheduling path) but the recorder must ALSO capture
    /// them — otherwise the recording is not the "realized note stream as it's
    /// produced" (spec Phase 0) and a replay dispatches silence for these steps.
    func test_recorder_capturesNoteRepeatTriggers_whenNoteRepeatActive() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (project, trackID) = makeNoteRepeatProject(interval: .oneSixtyFourth)
        controller.apply(documentModel: project)

        let recorder = controller.enableEventRecording()

        controller.start()
        // Tick 0 prepares the captured step; engage; then pump a few steps so the
        // note-repeat path SOUNDS repeated triggers.
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        for tick: UInt64 in 1...4 {
            controller.processTick(tickIndex: tick, now: Double(tick))
        }
        controller.stop()

        // The engine actually SOUNDED note-repeat triggers through the sink.
        let soundedNotes = sink.playedEvents.flatMap { $0 }
        XCTAssertFalse(
            soundedNotes.isEmpty,
            "fixture must sound note-repeat triggers through the dispatch path"
        )

        // The recorder must have captured the REALIZED stream that sounded — one
        // recorded event per sounded note-repeat trigger. With the prosecuted
        // defect, prepareTick masks the note-repeat track's prepared notes to []
        // (EngineController.swift:2277) before the recorder runs
        // (EngineController.swift:2293), so the recording holds FEWER events than
        // the dispatch path sounded — it is not the realized stream.
        let recorded = recorder.recordedEvents
        XCTAssertGreaterThanOrEqual(
            recorded.count, soundedNotes.count,
            "the recorder must capture at least every realized note the dispatch path " +
            "sounded; under the defect it records the MASKED ([]) prepared-notes map for " +
            "note-repeat tracks, so the recording is missing the repeated triggers " +
            "(recorded=\(recorded.count) < sounded=\(soundedNotes.count))"
        )
    }

    /// End-to-end byte-identity: record a live note-repeat run, replay the
    /// recording through a fresh engine driving the SAME dispatch path (WITHOUT
    /// re-engaging note-repeat — a recording is a self-contained realized stream),
    /// and assert the replay sounds the same notes the live run sounded. With the
    /// defect, the replay is silent because the masked recording held nothing.
    func test_replay_isByteIdenticalToLiveNoteRepeatRealization() {
        // 1) Live run with note-repeat engaged.
        let liveSink = CountingAudioSink()
        let liveController = EngineController(client: nil, endpoint: nil, audioOutput: liveSink)
        let (project, trackID) = makeNoteRepeatProject(interval: .oneSixtyFourth)
        liveController.apply(documentModel: project)
        let recorder = liveController.enableEventRecording()
        liveController.start()
        liveController.processTick(tickIndex: 0, now: 0)
        liveController.engageNoteRepeat(trackID: trackID)
        for tick: UInt64 in 1...4 {
            liveController.processTick(tickIndex: tick, now: Double(tick))
        }
        liveController.stop()

        let liveSounded = liveSink.playedEvents.flatMap { $0 }.map(\.pitch).sorted()
        XCTAssertFalse(liveSounded.isEmpty, "live note-repeat run must sound notes")

        let recordedNDJSON = recorder.serializedNDJSON()

        // 2) Replay the recording through a fresh engine — NO note-repeat engaged.
        //    The recording alone must reproduce the realized stream the live run
        //    sounded ("a replay is indistinguishable from a live realization").
        let replaySink = CountingAudioSink()
        let replayController = EngineController(client: nil, endpoint: nil, audioOutput: replaySink)
        replayController.apply(documentModel: project)
        replayController.beginEventReplay(EventReplaySource(ndjson: recordedNDJSON))
        replayController.start()
        for tick: UInt64 in 0...4 {
            replayController.processTick(tickIndex: tick, now: Double(tick))
        }
        replayController.stop()

        let replaySounded = replaySink.playedEvents.flatMap { $0 }.map(\.pitch).sorted()

        XCTAssertEqual(
            replaySounded, liveSounded,
            "replay of a note-repeat recording must reproduce the live realized stream " +
            "byte-identically; the defect masks the recording to empty, so replay is silent"
        )
    }
}
