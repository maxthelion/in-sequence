import AVFoundation
import XCTest
@testable import SequencerAI

final class EngineControllerShutdownTests: XCTestCase {
    func test_shutdown_stops_and_shuts_down_unique_hosts() {
        let host = CapturingShutdownAudioSink()
        let sampleEngine = CapturingShutdownSampleSink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutput: host,
            sampleEngine: sampleEngine
        )

        let track = StepSequenceTrack(
            name: "Lead",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        controller.apply(track: track)

        controller.shutdown()

        XCTAssertEqual(host.stopCallCount, 1)
        XCTAssertEqual(host.shutdownCallCount, 1)
        XCTAssertEqual(sampleEngine.stopCallCount, 1)
    }
}

private final class CapturingShutdownAudioSink: TrackPlaybackSink {
    let displayName = "Shutdown Host"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit?

    private(set) var stopCallCount = 0
    private(set) var shutdownCallCount = 0

    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() { stopCallCount += 1 }
    func shutdown() { shutdownCallCount += 1 }
    func setMix(_ mix: TrackMixSettings) {}
    func setDestination(_ destination: Destination) {}
    func selectInstrument(_ choice: AudioInstrumentChoice) { selectedInstrument = choice }
    func captureStateBlob() throws -> Data? { nil }
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {}
}

private final class CapturingShutdownSampleSink: SamplePlaybackSink {
    private(set) var stopCallCount = 0

    func start() throws {}
    func stop() { stopCallCount += 1 }
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? { nil }
    func setTrackMix(trackID: UUID, level: Double, pan: Double) {}
    func removeTrack(trackID: UUID) {}
    func audition(sampleURL: URL) {}
    func stopAudition() {}
    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {}
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {}
    func filterNode(for trackID: UUID) -> SamplerFilterNode? { nil }
}
