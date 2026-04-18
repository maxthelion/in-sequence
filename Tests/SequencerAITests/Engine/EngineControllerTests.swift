import XCTest
@testable import SequencerAI

final class EngineControllerTests: XCTestCase {
    func test_init_registers_core_blocks_and_builds_default_pipeline() {
        let controller = EngineController(client: nil, endpoint: nil)

        XCTAssertEqual(Set(controller.registeredKindIDs), ["note-generator", "midi-out"])
        XCTAssertNotNil(controller.executor)
    }

    func test_start_and_stop_toggle_running_state() {
        let controller = EngineController(client: nil, endpoint: nil)

        controller.start()
        XCTAssertTrue(controller.isRunning)

        controller.stop()
        XCTAssertFalse(controller.isRunning)
    }

    func test_setBPM_reaches_executor_within_two_ticks() {
        let controller = EngineController(client: nil, endpoint: nil)

        controller.setBPM(240)
        controller.start()
        controller.setBPM(120)

        let deadline = Date().addingTimeInterval(0.4)
        while controller.executor?.currentBPM != 120 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        controller.stop()
        XCTAssertEqual(controller.executor?.currentBPM, 120)
    }

    func test_apply_document_model_updates_note_generator_params() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let bass = StepSequenceTrack(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            name: "Bass",
            pitches: [36],
            stepPattern: [true, false],
            stepAccents: [false, false],
            output: .midiOut,
            velocity: 90,
            gateLength: 4
        )
        let lead = StepSequenceTrack(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
            name: "Lead",
            pitches: [72],
            stepPattern: [false, true],
            stepAccents: [false, true],
            output: .midiOut,
            mix: TrackMixSettings(level: 0.72, pan: -0.15, isMuted: false),
            velocity: 111,
            gateLength: 2
        )
        let document = SeqAIDocumentModel(
            version: 1,
            tracks: [bass, lead],
            selectedTrackID: lead.id
        )

        controller.apply(documentModel: document)

        let firstTick = controller.executor?.tick(now: 0)
        let secondTick = controller.executor?.tick(now: 0.1)

        guard case let .notes(firstNotes)? = firstTick?["gen"]?["notes"] else {
            return XCTFail("expected notes stream on first tick")
        }
        guard case let .notes(secondNotes)? = secondTick?["gen"]?["notes"] else {
            return XCTFail("expected notes stream on second tick")
        }

        XCTAssertTrue(firstNotes.isEmpty)
        XCTAssertEqual(secondNotes.count, 1)
        XCTAssertEqual(secondNotes.first?.pitch, 72)
        XCTAssertEqual(secondNotes.first?.velocity, 127)
        XCTAssertEqual(secondNotes.first?.length, 2)
        XCTAssertEqual(audioSink.receivedMixes.last, lead.mix)
    }

    func test_selected_au_output_routes_note_events_to_audio_sink() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let synthTrack = StepSequenceTrack(
            name: "Synth",
            pitches: [64],
            stepPattern: [true],
            stepAccents: [false],
            output: .auInstrument,
            audioInstrument: .testInstrument,
            mix: TrackMixSettings(level: 0.55, pan: 0.35, isMuted: false),
            velocity: 96,
            gateLength: 2
        )
        let document = SeqAIDocumentModel(
            version: 1,
            tracks: [synthTrack],
            selectedTrackID: synthTrack.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        XCTAssertEqual(audioSink.startCallCount, 1)
        XCTAssertEqual(audioSink.receivedEvents.first?.first?.pitch, 64)
        XCTAssertEqual(audioSink.receivedEvents.first?.first?.velocity, 96)
        XCTAssertEqual(audioSink.selectedInstrument, .testInstrument)
        XCTAssertEqual(controller.statusSummary, "Audio: Mock AU Instrument via Main Mixer")
        XCTAssertEqual(audioSink.receivedMixes.last, synthTrack.mix)
    }

    func test_muted_track_suppresses_audio_playback_and_updates_status() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let mutedTrack = StepSequenceTrack(
            name: "Muted",
            pitches: [67],
            stepPattern: [true],
            stepAccents: [false],
            output: .auInstrument,
            mix: TrackMixSettings(level: 0.9, pan: 0, isMuted: true),
            velocity: 100,
            gateLength: 2
        )

        controller.apply(track: mutedTrack)
        controller.processTick(tickIndex: 0, now: 0)

        XCTAssertTrue(audioSink.receivedEvents.isEmpty)
        XCTAssertEqual(controller.statusSummary, "Audio: Mock AU Instrument via Main Mixer (Muted)")
    }
}

private final class CapturingAudioSink: TrackPlaybackSink {
    let displayName = "Mock AU Instrument"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    private(set) var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var receivedEvents: [[NoteEvent]] = []
    private(set) var receivedMixes: [TrackMixSettings] = []

    func startIfNeeded() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func setMix(_ mix: TrackMixSettings) {
        receivedMixes.append(mix)
    }

    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }

    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        receivedEvents.append(noteEvents)
    }
}
