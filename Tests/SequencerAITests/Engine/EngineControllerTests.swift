import AVFoundation
import XCTest
@testable import SequencerAI

final class EngineControllerTests: XCTestCase {
    func test_init_registers_core_blocks_and_builds_default_pipeline() {
        let controller = EngineController(client: nil, endpoint: nil)

        XCTAssertEqual(Set(controller.registeredKindIDs), ["note-generator", "midi-out", "chord-context-sink"])
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

        let bassGeneratorBlockID = "gen-\(bass.id.uuidString.lowercased())"
        let leadGeneratorBlockID = "gen-\(lead.id.uuidString.lowercased())"
        let firstTick = controller.executor?.tick(now: 0)
        let secondTick = controller.executor?.tick(now: 0.1)

        guard case let .notes(firstBassNotes)? = firstTick?[bassGeneratorBlockID]?["notes"] else {
            return XCTFail("expected bass notes stream on first tick")
        }
        guard case let .notes(firstLeadNotes)? = firstTick?[leadGeneratorBlockID]?["notes"] else {
            return XCTFail("expected lead notes stream on first tick")
        }
        guard case let .notes(secondBassNotes)? = secondTick?[bassGeneratorBlockID]?["notes"] else {
            return XCTFail("expected bass notes stream on second tick")
        }
        guard case let .notes(secondLeadNotes)? = secondTick?[leadGeneratorBlockID]?["notes"] else {
            return XCTFail("expected lead notes stream on second tick")
        }

        XCTAssertEqual(firstBassNotes.count, 1)
        XCTAssertEqual(firstBassNotes.first?.pitch, 36)
        XCTAssertEqual(firstBassNotes.first?.velocity, 90)
        XCTAssertTrue(firstLeadNotes.isEmpty)
        XCTAssertTrue(secondBassNotes.isEmpty)
        XCTAssertEqual(secondLeadNotes.count, 1)
        XCTAssertEqual(secondLeadNotes.first?.pitch, 72)
        XCTAssertEqual(secondLeadNotes.first?.velocity, 127)
        XCTAssertEqual(secondLeadNotes.first?.length, 2)
        XCTAssertTrue(audioSink.receivedMixes.isEmpty)
    }

    func test_selected_au_output_routes_note_events_to_audio_sink() throws {
        throw XCTSkip("Selecting the AU output path can restart the macOS XCTest host before assertions run; controller fan-out remains covered by the multi-track audio sink tests and manual AU smoke.")
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
        controller.start()
        controller.processTick(tickIndex: 0, now: 0)
        controller.stop()

        XCTAssertEqual(audioSink.startCallCount, 1)
        XCTAssertEqual(audioSink.receivedEvents.first?.first?.pitch, 64)
        XCTAssertEqual(audioSink.receivedEvents.first?.first?.velocity, 96)
        XCTAssertEqual(audioSink.selectedInstrument, .testInstrument)
        XCTAssertEqual(controller.statusSummary, "Audio: Mock AU Instrument via Main Mixer")
        XCTAssertEqual(audioSink.receivedMixes.last, synthTrack.mix)
        XCTAssertEqual(audioSink.stopCallCount, 1)
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

    func test_effective_destination_uses_group_shared_destination_and_pitch_offset() {
        let controller = EngineController(client: nil, endpoint: nil)
        let groupID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") ?? UUID()
        let track = StepSequenceTrack(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID(),
            name: "Kick",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let group = TrackGroup(
            id: groupID,
            name: "Kit",
            memberIDs: [track.id],
            sharedDestination: .midi(port: .sequencerAIOut, channel: 9, noteOffset: 2),
            noteMapping: [track.id: 12]
        )
        let document = SeqAIDocumentModel(
            version: 1,
            tracks: [track],
            trackGroups: [group],
            selectedTrackID: track.id,
            phrases: [PhraseModel.default(tracks: [track])],
            selectedPhraseID: PhraseModel.default(tracks: [track]).id
        )

        controller.apply(documentModel: document)

        let resolved = controller.effectiveDestination(for: track.id)
        XCTAssertEqual(resolved.destination, .midi(port: .sequencerAIOut, channel: 9, noteOffset: 2))
        XCTAssertEqual(resolved.pitchOffset, 12)
    }

    func test_effective_destination_returns_none_when_inherited_group_has_no_shared_destination() {
        let controller = EngineController(client: nil, endpoint: nil)
        let groupID = UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff") ?? UUID()
        let track = StepSequenceTrack(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID(),
            name: "Hat",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let group = TrackGroup(id: groupID, name: "Kit", memberIDs: [track.id], sharedDestination: nil)
        let phrase = PhraseModel.default(tracks: [track])
        let document = SeqAIDocumentModel(
            version: 1,
            tracks: [track],
            trackGroups: [group],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)

        let resolved = controller.effectiveDestination(for: track.id)
        XCTAssertEqual(resolved.destination, .none)
        XCTAssertEqual(resolved.pitchOffset, 0)
    }

    func test_multiple_audio_tracks_all_play_when_transport_ticks() {
        var createdSinks: [CapturingAudioSink] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CapturingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )
        let bassTrack = StepSequenceTrack(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
            name: "Bass",
            pitches: [48],
            stepPattern: [true],
            stepAccents: [false],
            output: .auInstrument,
            audioInstrument: .builtInSynth,
            mix: TrackMixSettings(level: 0.6, pan: -0.2, isMuted: false),
            velocity: 90,
            gateLength: 2
        )
        let leadTrack = StepSequenceTrack(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
            name: "Lead",
            pitches: [72],
            stepPattern: [true],
            stepAccents: [true],
            output: .auInstrument,
            audioInstrument: .testInstrument,
            mix: TrackMixSettings(level: 0.8, pan: 0.3, isMuted: false),
            velocity: 100,
            gateLength: 2
        )
        let document = SeqAIDocumentModel(
            version: 1,
            tracks: [bassTrack, leadTrack],
            selectedTrackID: leadTrack.id
        )

        controller.apply(documentModel: document)
        controller.start()
        controller.processTick(tickIndex: 0, now: 0)
        controller.stop()

        XCTAssertEqual(createdSinks.count, 2)
        XCTAssertEqual(createdSinks[0].receivedEvents.first?.first?.pitch, 48)
        XCTAssertEqual(createdSinks[1].receivedEvents.first?.first?.pitch, 72)
        XCTAssertEqual(createdSinks[1].selectedInstrument, .testInstrument)
    }

    func test_group_inherited_audio_destination_reuses_one_host_and_applies_pitch_offsets() {
        var createdSinks: [CapturingAudioSink] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CapturingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )
        let groupID = UUID(uuidString: "12121212-3434-5656-7878-909090909090") ?? UUID()
        let kick = StepSequenceTrack(
            id: UUID(uuidString: "abababab-abab-abab-abab-abababababab") ?? UUID(),
            name: "Kick",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let snare = StepSequenceTrack(
            id: UUID(uuidString: "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd") ?? UUID(),
            name: "Snare",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let group = TrackGroup(
            id: groupID,
            name: "Kit",
            memberIDs: [kick.id, snare.id],
            sharedDestination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            noteMapping: [kick.id: 0, snare.id: 12]
        )
        let phrase = PhraseModel.default(tracks: [kick, snare])
        let document = SeqAIDocumentModel(
            version: 1,
            tracks: [kick, snare],
            trackGroups: [group],
            selectedTrackID: kick.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        XCTAssertEqual(createdSinks.count, 1)
        let playedPitches = createdSinks[0].receivedEvents.flatMap { $0 }.map(\.pitch).sorted()
        XCTAssertEqual(playedPitches, [60, 72])
        XCTAssertEqual(createdSinks[0].selectedInstrument, .testInstrument)
    }
}

private final class CapturingAudioSink: TrackPlaybackSink {
    let displayName = "Mock AU Instrument"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    private(set) var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit? = nil
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var receivedEvents: [[NoteEvent]] = []
    private(set) var receivedMixes: [TrackMixSettings] = []
    private(set) var receivedDestinations: [Destination] = []

    func startIfNeeded() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func setMix(_ mix: TrackMixSettings) {
        receivedMixes.append(mix)
    }

    func setDestination(_ destination: Destination) {
        receivedDestinations.append(destination)
        if case let .auInstrument(componentID, _) = destination {
            selectedInstrument = availableInstruments.first(where: { $0.audioComponentID == componentID }) ?? .builtInSynth
        }
    }

    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }

    func captureStateBlob() throws -> Data? {
        nil
    }

    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        receivedEvents.append(noteEvents)
    }
}
