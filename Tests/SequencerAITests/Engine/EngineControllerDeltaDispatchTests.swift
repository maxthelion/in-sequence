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
