import AVFoundation
import XCTest
@testable import SequencerAI

final class EngineControllerDeltaDispatchTests: XCTestCase {
    func test_apply_mix_only_delta_updates_host_without_resyncing_destinations() {
        let host = CapturingDeltaAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: host)

        let track = StepSequenceTrack(
            name: "Lead",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, initialClipID: nil)],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        controller.apply(documentModel: project)

        let prepareCountBefore = host.prepareCallCount
        let destinationCountBefore = host.destinationCount

        var changed = project
        changed.tracks[0].mix.level = 0.33

        controller.apply(documentModel: changed)

        XCTAssertEqual(host.receivedMixes.last, changed.tracks[0].mix)
        XCTAssertEqual(host.prepareCallCount, prepareCountBefore)
        XCTAssertEqual(host.destinationCount, destinationCountBefore)
    }

    func test_apply_selected_track_only_delta_updates_selected_output_without_broad_sync() {
        let host = CapturingDeltaAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: host)

        let first = StepSequenceTrack(
            name: "First",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 100,
            gateLength: 4
        )
        let second = StepSequenceTrack(
            name: "Second",
            trackType: .monoMelodic,
            pitches: [64],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [first, second])
        let phrase = PhraseModel.default(
            tracks: [first, second],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        let project = Project(
            version: 1,
            tracks: [first, second],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [
                TrackPatternBank.default(for: first, initialClipID: nil),
                TrackPatternBank.default(for: second, initialClipID: nil),
            ],
            selectedTrackID: second.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: project)
        let prepareCountBefore = host.prepareCallCount
        let destinationCountBefore = host.destinationCount

        var changed = project
        changed.selectTrack(id: first.id)
        controller.apply(documentModel: changed)

        XCTAssertEqual(controller.selectedOutput, .midi)
        XCTAssertEqual(host.prepareCallCount, prepareCountBefore)
        XCTAssertEqual(host.destinationCount, destinationCountBefore)
    }

    func test_apply_clip_pool_only_delta_does_not_resync_audio_host() {
        let host = CapturingDeltaAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: host)

        let track = StepSequenceTrack(
            name: "Lead",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let clipID = UUID(uuidString: "50505050-5050-5050-5050-505050505050")!
        let clip = ClipPoolEntry(
            id: clipID,
            name: "Lead Clip",
            trackType: track.trackType,
            content: .emptyNoteGrid(lengthSteps: 16)
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip]
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, initialClipID: clipID)],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        controller.apply(documentModel: project)

        let prepareCountBefore = host.prepareCallCount
        let destinationCountBefore = host.destinationCount
        let mixCountBefore = host.receivedMixes.count

        var changed = project
        changed.clipPool[0].content = .noteGrid(
            lengthSteps: 16,
            steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)]), fill: nil)]
                + Array(repeating: .empty, count: 15)
        )

        controller.apply(documentModel: changed)

        XCTAssertEqual(host.prepareCallCount, prepareCountBefore)
        XCTAssertEqual(host.destinationCount, destinationCountBefore)
        XCTAssertEqual(host.receivedMixes.count, mixCountBefore)
    }

    func test_apply_pattern_bank_only_delta_does_not_resync_audio_host() {
        let host = CapturingDeltaAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: host)

        let track = StepSequenceTrack(
            name: "Lead",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, initialClipID: nil)],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        controller.apply(documentModel: project)

        let prepareCountBefore = host.prepareCallCount
        let destinationCountBefore = host.destinationCount
        let mixCountBefore = host.receivedMixes.count

        var changed = project
        let clipID = UUID(uuidString: "60606060-6060-6060-6060-606060606060")!
        var bank = changed.patternBanks[0]
        let existing = bank.slot(at: 0)
        bank.setSlot(
            TrackPatternSlot(
                slotIndex: 0,
                name: existing.name,
                sourceRef: SourceRef(
                    mode: .clip,
                    generatorID: existing.sourceRef.generatorID,
                    clipID: clipID,
                    modifierGeneratorID: existing.sourceRef.modifierGeneratorID,
                    modifierBypassed: existing.sourceRef.modifierBypassed
                )
            ),
            at: 0
        )
        changed.patternBanks[0] = bank
        changed.clipPool = [
            ClipPoolEntry(
                id: clipID,
                name: "Lead Clip",
                trackType: track.trackType,
                content: .emptyNoteGrid(lengthSteps: 16)
            )
        ]

        controller.apply(documentModel: changed)

        XCTAssertEqual(host.prepareCallCount, prepareCountBefore)
        XCTAssertEqual(host.destinationCount, destinationCountBefore)
        XCTAssertEqual(host.receivedMixes.count, mixCountBefore)
    }
}

private final class CapturingDeltaAudioSink: TrackPlaybackSink {
    let displayName = "Delta Dispatch Host"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit?

    private(set) var prepareCallCount = 0
    private(set) var destinationCount = 0
    private(set) var receivedMixes: [TrackMixSettings] = []

    func prepareIfNeeded() {
        prepareCallCount += 1
    }

    func startIfNeeded() {}
    func stop() {}
    func shutdown() {}

    func setMix(_ mix: TrackMixSettings) {
        receivedMixes.append(mix)
    }

    func setDestination(_ destination: Destination) {
        destinationCount += 1
    }

    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }

    func captureStateBlob() throws -> Data? { nil }
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {}
}
