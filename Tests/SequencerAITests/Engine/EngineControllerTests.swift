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
        let bass = StepSequenceTrack(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            name: "Bass",
            pitches: [36],
            stepPattern: [true, false],
            stepAccents: [false, false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 90,
            gateLength: 4
        )
        let lead = StepSequenceTrack(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
            name: "Lead",
            pitches: [72],
            stepPattern: [false, true],
            stepAccents: [false, true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            mix: TrackMixSettings(level: 0.72, pan: -0.15, isMuted: false),
            velocity: 111,
            gateLength: 2
        )
        let bassGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!,
            name: "Bass Program",
            trackType: bass.trackType,
            pattern: [true, false],
            pitch: 36,
            velocity: 90,
            gateLength: 4
        )
        let leadGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "bbbbbbbb-2222-2222-2222-222222222222")!,
            name: "Lead Program",
            trackType: lead.trackType,
            pattern: [false, true],
            pitch: 72,
            velocity: 127,
            gateLength: 2
        )
        let generators = [bassGenerator, leadGenerator]
        let layers = PhraseLayerDefinition.defaultSet(for: [bass, lead])
        let phrase = PhraseModel.default(tracks: [bass, lead], layers: layers, generatorPool: generators, clipPool: [])
        let patternBanks = [
            TrackPatternBank(
                trackID: bass.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(bassGenerator.id))]
            ),
            TrackPatternBank(
                trackID: lead.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(leadGenerator.id))]
            )
        ]
        let document = Project(
            version: 1,
            tracks: [bass, lead],
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: patternBanks,
            selectedTrackID: lead.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)
        controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(createdSinks.count, 2)
        XCTAssertEqual(createdSinks[0].receivedEvents.flatMap { $0 }.map(\.pitch), [36])
        XCTAssertEqual(createdSinks[0].receivedEvents.flatMap { $0 }.map(\.velocity), [90])
        XCTAssertEqual(createdSinks[1].receivedEvents.flatMap { $0 }.map(\.pitch), [72])
        XCTAssertEqual(createdSinks[1].receivedEvents.flatMap { $0 }.map(\.velocity), [127])
        XCTAssertEqual(createdSinks[1].receivedEvents.flatMap { $0 }.map(\.length), [2])
    }

    func test_apply_document_model_uses_selected_generator_pool_source_over_legacy_track_fields() throws {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212") ?? UUID(),
            name: "Generator Driven",
            pitches: [48],
            stepPattern: [false, false, false, false],
            stepAccents: [false, false, false, false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 80,
            gateLength: 2
        )
        let generator = GeneratorPoolEntry(
            id: UUID(uuidString: "34343434-3434-3434-3434-343434343434")!,
            name: "Upbeat",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.manual(pattern: [true, false, false, false])),
                pitch: .native(.manual(pitches: [72], pickMode: .sequential)),
                shape: NoteShape(velocity: 99, gateLength: 3, accent: false)
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.pitch, 72)
        XCTAssertEqual(events.first?.velocity, 99)
        XCTAssertEqual(events.first?.length, 3)
    }

    func test_apply_document_model_uses_selected_clip_source_over_legacy_track_fields() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "56565656-5656-5656-5656-565656565656") ?? UUID(),
            name: "Clip Driven",
            pitches: [48],
            stepPattern: [false, false, false, false],
            stepAccents: [false, false, false, false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 80,
            gateLength: 2
        )
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "78787878-7878-7878-7878-787878787878")!,
            name: "Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: [true, false, false, false], pitches: [65])
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [clip])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let document = Project(
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

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.pitch, 65)
        XCTAssertEqual(events.first?.velocity, 100)
        XCTAssertEqual(events.first?.length, 4)
    }

    func test_process_tick_marks_recent_note_trigger_when_selected_source_emits_notes() {
        let controller = EngineController(client: nil, endpoint: nil)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "90909090-9090-9090-9090-909090909090") ?? UUID(),
            name: "Activity",
            pitches: [48],
            stepPattern: [false, false, false, false],
            stepAccents: [false, false, false, false],
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 80,
            gateLength: 2
        )
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "91919191-9191-9191-9191-919191919191")!,
            name: "Activity Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: [true, false, false, false], pitches: [67])
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [clip])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let document = Project(
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

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 12.5)

        XCTAssertEqual(controller.lastNoteTriggerUptime, 12.5)
        XCTAssertEqual(controller.lastNoteTriggerCount, 1)
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
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            mix: TrackMixSettings(level: 0.55, pan: 0.35, isMuted: false),
            velocity: 96,
            gateLength: 2
        )
        let document = Project(
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
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
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
        let document = Project(
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
        let document = Project(
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
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
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
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            mix: TrackMixSettings(level: 0.8, pan: 0.3, isMuted: false),
            velocity: 100,
            gateLength: 2
        )
        let bassGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "cccccccc-3333-3333-3333-333333333333")!,
            name: "Bass Audio Program",
            trackType: bassTrack.trackType,
            pattern: [true],
            pitch: 48,
            velocity: 90,
            gateLength: 2
        )
        let leadGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "dddddddd-4444-4444-4444-444444444444")!,
            name: "Lead Audio Program",
            trackType: leadTrack.trackType,
            pattern: [true],
            pitch: 72,
            velocity: 100,
            gateLength: 2
        )
        let generators = [bassGenerator, leadGenerator]
        let layers = PhraseLayerDefinition.defaultSet(for: [bassTrack, leadTrack])
        let phrase = PhraseModel.default(tracks: [bassTrack, leadTrack], layers: layers, generatorPool: generators, clipPool: [])
        let patternBanks = [
            TrackPatternBank(
                trackID: bassTrack.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(bassGenerator.id))]
            ),
            TrackPatternBank(
                trackID: leadTrack.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(leadGenerator.id))]
            )
        ]
        let document = Project(
            version: 1,
            tracks: [bassTrack, leadTrack],
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: patternBanks,
            selectedTrackID: leadTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
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

    func test_apply_document_model_prepares_audio_unit_hosts_before_playback() {
        let sink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let track = StepSequenceTrack(
            name: "Prepared",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 2
        )

        controller.apply(track: track)

        XCTAssertGreaterThanOrEqual(sink.prepareCallCount, 1)
    }

    func test_processTick_doesNotReapplyUnchangedAudioDestinationEveryDispatch() {
        let sink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let track = StepSequenceTrack(
            name: "Stable AU",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 2
        )

        controller.apply(track: track)
        XCTAssertEqual(sink.receivedDestinations.count, 1)

        controller.processTick(tickIndex: 0, now: 0)
        controller.processTick(tickIndex: 1, now: 0.1)
        controller.processTick(tickIndex: 2, now: 0.2)

        XCTAssertEqual(sink.receivedDestinations.count, 1)
        XCTAssertEqual(sink.receivedEvents.count, 3)
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
        let kickGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "eeeeeeee-5555-5555-5555-555555555555")!,
            name: "Kick Program",
            trackType: kick.trackType,
            pattern: [true],
            pitch: 60,
            velocity: 100,
            gateLength: 2
        )
        let snareGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "ffffffff-6666-6666-6666-666666666666")!,
            name: "Snare Program",
            trackType: snare.trackType,
            pattern: [true],
            pitch: 60,
            velocity: 100,
            gateLength: 2
        )
        let generators = [kickGenerator, snareGenerator]
        let layers = PhraseLayerDefinition.defaultSet(for: [kick, snare])
        let phrase = PhraseModel.default(tracks: [kick, snare], layers: layers, generatorPool: generators, clipPool: [])
        let patternBanks = [
            TrackPatternBank(
                trackID: kick.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(kickGenerator.id))]
            ),
            TrackPatternBank(
                trackID: snare.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(snareGenerator.id))]
            )
        ]
        let document = Project(
            version: 1,
            tracks: [kick, snare],
            trackGroups: [group],
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: patternBanks,
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

private func monoGeneratorEntry(
    id: UUID,
    name: String,
    trackType: TrackType,
    pattern: [Bool],
    pitch: Int,
    velocity: Int,
    gateLength: Int
) -> GeneratorPoolEntry {
    GeneratorPoolEntry(
        id: id,
        name: name,
        trackType: trackType,
        kind: .monoGenerator,
        params: .mono(
            trigger: .native(.manual(pattern: pattern)),
            pitch: .native(.manual(pitches: [pitch], pickMode: .sequential)),
            shape: NoteShape(velocity: velocity, gateLength: gateLength, accent: false)
        )
    )
}

private final class CapturingAudioSink: TrackPlaybackSink {
    let displayName = "Mock AU Instrument"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    private(set) var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit? = nil
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var prepareCallCount = 0
    private(set) var receivedEvents: [[NoteEvent]] = []
    private(set) var receivedMixes: [TrackMixSettings] = []
    private(set) var receivedDestinations: [Destination] = []

    func prepareIfNeeded() {
        prepareCallCount += 1
    }

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
