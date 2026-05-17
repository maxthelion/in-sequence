import AVFoundation
import XCTest
@testable import SequencerAI

final class EngineControllerMixerBusTests: XCTestCase {
    func test_applyDocumentModel_propagatesTrackOutputBusToAUInstrumentHostAndClearsAfterBusDeletion() {
        let busID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let host = CapturingMixerBusAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: host)
        var project = Self.project(
            tracks: [
                Self.track(
                    name: "Lead",
                    trackType: .monoMelodic,
                    destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
                    outputBusID: busID
                ),
            ],
            buses: [MixerBus(id: busID, name: "Lead Bus")]
        )

        controller.apply(documentModel: project)

        XCTAssertEqual(host.outputBusIDs, [busID])

        project.deleteMixerBus(id: busID)
        controller.apply(documentModel: project)

        XCTAssertEqual(host.outputBusIDs, [busID, nil])
    }

    func test_applyDocumentModel_propagatesTrackOutputBusToSampleAndSlicerSinksAndClearsToMaster() {
        let busID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let sampleTrack = Self.track(
            name: "Kick",
            trackType: .slice,
            destination: .sample(sampleID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, settings: .default),
            outputBusID: busID
        )
        let slicerTrack = Self.track(
            name: "Break",
            trackType: .slice,
            destination: .slicer(sliceSetID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, settings: .default),
            outputBusID: busID
        )
        let sampleEngine = CapturingMixerBusSampleSink()
        let controller = EngineController(client: nil, endpoint: nil, sampleEngine: sampleEngine)
        var project = Self.project(
            tracks: [sampleTrack, slicerTrack],
            buses: [MixerBus(id: busID, name: "Drum Bus")]
        )

        controller.apply(documentModel: project)

        XCTAssertEqual(
            sampleEngine.outputBusCalls,
            [
                .init(trackID: sampleTrack.id, busID: busID),
                .init(trackID: slicerTrack.id, busID: busID),
            ]
        )

        project.setTrackOutputBus(trackID: sampleTrack.id, busID: nil)
        project.setTrackOutputBus(trackID: slicerTrack.id, busID: nil)
        controller.apply(documentModel: project)

        XCTAssertEqual(
            sampleEngine.outputBusCalls,
            [
                .init(trackID: sampleTrack.id, busID: busID),
                .init(trackID: slicerTrack.id, busID: busID),
                .init(trackID: sampleTrack.id, busID: nil),
                .init(trackID: slicerTrack.id, busID: nil),
            ]
        )
    }

    func test_effectiveMute_usesAuthoredMuteWhenNoSoloIsActive() {
        var project = Self.project()
        project.tracks[0].mix.isMuted = true
        project.buses[0].mix.isMuted = true

        let state = EngineController.effectiveMixerMuteState(for: project)

        XCTAssertFalse(state.isSoloActive)
        XCTAssertEqual(state.mutedTrackIDs, [project.tracks[0].id])
        XCTAssertEqual(state.mutedBusIDs, [project.buses[0].id])
    }

    func test_effectiveMute_soloedBusAudiblyCarriesRoutedTracksAndMutesDirectMasterTracks() {
        var project = Self.project()
        project.buses[0].mix.isSoloed = true

        let state = EngineController.effectiveMixerMuteState(for: project)

        XCTAssertTrue(state.isSoloActive)
        XCTAssertFalse(state.mutedTrackIDs.contains(project.tracks[0].id))
        XCTAssertTrue(state.mutedTrackIDs.contains(project.tracks[1].id))
        XCTAssertFalse(state.mutedBusIDs.contains(project.buses[0].id))
        XCTAssertTrue(state.mutedBusIDs.contains(project.buses[1].id))
    }

    func test_effectiveMute_soloedTrackKeepsItsBusPathOpenWithoutPersistingMembership() {
        var project = Self.project()
        project.tracks[0].mix.isSoloed = true

        let state = EngineController.effectiveMixerMuteState(for: project)

        XCTAssertTrue(state.isSoloActive)
        XCTAssertFalse(state.mutedTrackIDs.contains(project.tracks[0].id))
        XCTAssertTrue(state.mutedTrackIDs.contains(project.tracks[1].id))
        XCTAssertFalse(state.mutedBusIDs.contains(project.buses[0].id))
        XCTAssertTrue(state.mutedBusIDs.contains(project.buses[1].id))
        XCTAssertTrue(project.buses.allSatisfy { !$0.mix.isSoloed })
    }

    func test_effectiveMute_clearSoloFallsBackToAuthoredMuteOnly() {
        var project = Self.project()
        project.tracks[0].mix.isSoloed = true
        project.buses[1].mix.isSoloed = true

        project.clearAllSolo()
        let state = EngineController.effectiveMixerMuteState(for: project)

        XCTAssertFalse(state.isSoloActive)
        XCTAssertTrue(state.mutedTrackIDs.isEmpty)
        XCTAssertTrue(state.mutedBusIDs.isEmpty)
        XCTAssertFalse(project.tracks.contains { $0.mix.isSoloed })
        XCTAssertFalse(project.buses.contains { $0.mix.isSoloed })
    }

    private static func track(
        id: UUID = UUID(),
        name: String,
        trackType: TrackType,
        destination: Destination,
        outputBusID: UUID?
    ) -> StepSequenceTrack {
        StepSequenceTrack(
            id: id,
            name: name,
            trackType: trackType,
            pitches: [60],
            stepPattern: [true],
            destination: destination,
            outputBusID: outputBusID,
            velocity: 100,
            gateLength: 4
        )
    }

    private static func project(tracks: [StepSequenceTrack], buses: [MixerBus]) -> Project {
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        return Project(
            version: 1,
            tracks: tracks,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            buses: buses,
            patternBanks: tracks.map { TrackPatternBank.default(for: $0, initialClipID: nil) },
            selectedTrackID: tracks[0].id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }

    private static func project() -> Project {
        let busA = MixerBus(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!, name: "Drums")
        let busB = MixerBus(id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!, name: "FX")
        let routedTrack = StepSequenceTrack(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Kick",
            trackType: .slice,
            pitches: [36],
            stepPattern: [true],
            destination: .sample(sampleID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, settings: .default),
            outputBusID: busA.id,
            velocity: 100,
            gateLength: 4
        )
        let directTrack = StepSequenceTrack(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Lead",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [routedTrack, directTrack])
        let phrase = PhraseModel.default(
            tracks: [routedTrack, directTrack],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        return Project(
            version: 1,
            tracks: [routedTrack, directTrack],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            buses: [busA, busB],
            patternBanks: [
                TrackPatternBank.default(for: routedTrack, initialClipID: nil),
                TrackPatternBank.default(for: directTrack, initialClipID: nil),
            ],
            selectedTrackID: routedTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }
}

private final class CapturingMixerBusAudioSink: TrackPlaybackSink {
    let displayName = "Mixer Bus AU Host"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit?
    private(set) var outputBusIDs: [UUID?] = []

    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() {}
    func shutdown() {}
    func setMix(_ mix: TrackMixSettings) {}

    func setOutputBusID(_ busID: UUID?) {
        outputBusIDs.append(busID)
    }

    func setDestination(_ destination: Destination) {}
    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }

    func captureStateBlob() throws -> Data? { nil }
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {}
}

private final class CapturingMixerBusSampleSink: SamplePlaybackSink {
    struct OutputBusCall: Equatable {
        let trackID: UUID
        let busID: UUID?
    }

    private(set) var outputBusCalls: [OutputBusCall] = []

    func start() throws {}
    func stop() {}
    func prepareTrack(trackID: UUID) {}
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? { nil }
    func setTrackMix(trackID: UUID, level: Double, pan: Double) {}

    func setTrackOutputBus(trackID: UUID, busID: UUID?) {
        outputBusCalls.append(OutputBusCall(trackID: trackID, busID: busID))
    }

    func removeTrack(trackID: UUID) {}
    func audition(sampleURL: URL) {}
    func stopAudition() {}
    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {}
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {}
    func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? { nil }
}
