import AVFoundation
import XCTest
@testable import SequencerAI

final class EngineControllerSetMixScopedTests: XCTestCase {
    func test_setMix_updates_audio_host_without_reapplying_document() {
        let host = CapturingScopedAudioSink()
        let sampleEngine = CapturingScopedSampleSink()
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

        let prepareCountBefore = host.prepareCallCount
        let destinationCountBefore = host.destinationCount
        let mix = TrackMixSettings(level: 0.42, pan: -0.3, isMuted: false)

        controller.setMix(trackID: track.id, mix: mix)

        XCTAssertEqual(host.receivedMixes.last, mix)
        XCTAssertEqual(host.prepareCallCount, prepareCountBefore, "scoped setMix should not rebuild/prepare the audio host")
        XCTAssertEqual(host.destinationCount, destinationCountBefore, "scoped setMix should not resend destinations")
        XCTAssertTrue(sampleEngine.calls.isEmpty, "non-sample tracks must not hit sampleEngine.setTrackMix")
    }

    func test_setMix_updates_sample_engine_for_sample_tracks() {
        let sampleEngine = CapturingScopedSampleSink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: sampleEngine
        )

        let track = StepSequenceTrack(
            name: "Kick",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .sample(sampleID: UUID(), settings: .default),
            velocity: 100,
            gateLength: 4
        )
        controller.apply(track: track)

        let baselineCallCount = sampleEngine.calls.count
        let mix = TrackMixSettings(level: 0.25, pan: -0.5, isMuted: false)

        controller.setMix(trackID: track.id, mix: mix)

        let newCalls = Array(sampleEngine.calls.dropFirst(baselineCallCount))
        XCTAssertEqual(newCalls.count, 1)
        XCTAssertEqual(newCalls.first, .setTrackMix(trackID: track.id, level: 0.25, pan: -0.5))
    }

    func test_setMix_for_unknown_track_is_noop() {
        let host = CapturingScopedAudioSink()
        let sampleEngine = CapturingScopedSampleSink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutput: host,
            sampleEngine: sampleEngine
        )

        controller.setMix(trackID: UUID(), mix: .default)

        XCTAssertTrue(host.receivedMixes.isEmpty)
        XCTAssertTrue(sampleEngine.calls.isEmpty)
    }
}

private final class CapturingScopedAudioSink: TrackPlaybackSink {
    let displayName = "Scoped Mix Host"
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

private final class CapturingScopedSampleSink: SamplePlaybackSink {
    enum Call: Equatable {
        case start
        case stop
        case play(trackID: UUID)
        case setTrackMix(trackID: UUID, level: Double, pan: Double)
        case removeTrack(trackID: UUID)
        case audition
        case stopAudition
    }

    private(set) var calls: [Call] = []

    func start() throws {
        calls.append(.start)
    }

    func stop() {
        calls.append(.stop)
    }

    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
        calls.append(.play(trackID: trackID))
        return nil
    }

    func setTrackMix(trackID: UUID, level: Double, pan: Double) {
        calls.append(.setTrackMix(trackID: trackID, level: level, pan: pan))
    }

    func removeTrack(trackID: UUID) {
        calls.append(.removeTrack(trackID: trackID))
    }

    func audition(sampleURL: URL) {
        calls.append(.audition)
    }

    func stopAudition() {
        calls.append(.stopAudition)
    }

    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {}
}
