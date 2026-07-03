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
        let mix = TrackMixSettings(level: 0.25, pan: -0.5, isMuted: false, sendA: 0.35, sendB: 0.65)

        controller.setMix(trackID: track.id, mix: mix)

        let newCalls = Array(sampleEngine.calls.dropFirst(baselineCallCount))
        XCTAssertEqual(newCalls, [
            .setTrackMix(trackID: track.id, level: 0.25, pan: -0.5),
            .setTrackMuteGain(trackID: track.id, muted: false),
            .setTrackSceneGain(trackID: track.id, gain: 1),
            .setTrackSends(trackID: track.id, sendA: 0.35, sendB: 0.65),
        ])
    }

    /// Mute convention (b4701881): the fader level sent to `setTrackMix` stays
    /// the RAW user value — mute is a separate ramped gain (`setTrackMuteGain`)
    /// so unmute restores the fader without a hard-cut. (This test previously
    /// pinned the pre-b4701881 zeroed-level contract and was stale-red.)
    func test_setMix_for_muted_sample_track_keeps_raw_level_and_ramps_mute_gain() {
        let sampleEngine = CapturingScopedSampleSink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: sampleEngine
        )

        let track = StepSequenceTrack(
            name: "Muted Kick",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .sample(sampleID: UUID(), settings: .default),
            velocity: 100,
            gateLength: 4
        )
        controller.apply(track: track)

        let baselineCallCount = sampleEngine.calls.count
        let mix = TrackMixSettings(level: 0.9, pan: 0.25, isMuted: true, sendA: 0.4, sendB: 0.7)

        controller.setMix(trackID: track.id, mix: mix)

        let newCalls = Array(sampleEngine.calls.dropFirst(baselineCallCount))
        XCTAssertEqual(newCalls, [
            .setTrackMix(trackID: track.id, level: 0.9, pan: 0.25),
            .setTrackMuteGain(trackID: track.id, muted: true),
            .setTrackSceneGain(trackID: track.id, gain: 1),
            .setTrackSends(trackID: track.id, sendA: 0.4, sendB: 0.7),
        ])
    }

    /// WS6 (selective scene inputs): a B-only track at a full-A crossfader gets
    /// scene gain 0 through the RAMPED scene-gain stage — the raw fader level
    /// still rides `setTrackMix` untouched, and the Send A/B values are
    /// byte-identical to the pre-WS6 contract (353829be hard line).
    func test_setMix_sceneMembership_ridesRampedSceneGainStage_sendsUntouched() {
        let sampleEngine = CapturingScopedSampleSink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: sampleEngine
        )

        let track = StepSequenceTrack(
            name: "B Only Kick",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .sample(sampleID: UUID(), settings: .default),
            velocity: 100,
            gateLength: 4
        )
        controller.apply(track: track)
        // Full A: the live crossfader override is the deterministic source the
        // membership gain derives from.
        controller.setLiveMasterCrossfader(0)

        let baselineCallCount = sampleEngine.calls.count
        let mix = TrackMixSettings(
            level: 0.75,
            pan: 0,
            isMuted: false,
            sceneMembership: .sceneB,
            sendA: 0.2,
            sendB: 0.3
        )

        controller.setMix(trackID: track.id, mix: mix)

        let newCalls = Array(sampleEngine.calls.dropFirst(baselineCallCount))
        XCTAssertEqual(newCalls, [
            .setTrackMix(trackID: track.id, level: 0.75, pan: 0),
            .setTrackMuteGain(trackID: track.id, muted: false),
            .setTrackSceneGain(trackID: track.id, gain: 0),
            .setTrackSends(trackID: track.id, sendA: 0.2, sendB: 0.3),
        ])

        // Crossfade to full B: the same membership now plays at unity, again
        // through the ramped scene-gain stage (no document re-apply).
        controller.setLiveMasterCrossfader(1)
        XCTAssertEqual(
            sampleEngine.calls.last(where: {
                if case .setTrackSceneGain = $0 { return true }
                return false
            }),
            .setTrackSceneGain(trackID: track.id, gain: 1)
        )
    }

    /// Mixer render-livelock invariant (RT-7 / send-amount-hang fix): a scoped
    /// per-drag `setMix` must NOT bump the observed `documentModelUIRevision`.
    /// That revision is the ONLY observation trigger for `currentDocumentModel`-
    /// derived UI (now @ObservationIgnored); if `setMix` bumped it, a continuous
    /// send/fader drag would re-trigger the synchronous SwiftUI layout fan-out
    /// per mouse-move — the cycle that deadlocked the tick + audio render.
    func test_setMix_does_not_bump_document_model_ui_revision() {
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

        // A full document apply (apply(track:)) is a structural change and MUST
        // bump the UI revision so summaries like TransportBar.statusSummary refresh.
        let revisionAfterApply = controller.documentModelUIRevision
        XCTAssertGreaterThan(revisionAfterApply, 0, "document apply should bump the UI revision")

        // Simulate a continuous send-amount drag: many scoped setMix calls.
        for step in 0..<32 {
            let value = Double(step) / 32.0
            controller.setMix(
                trackID: track.id,
                mix: TrackMixSettings(level: 0.5, pan: 0, isMuted: false, sendA: value, sendB: 0)
            )
        }

        XCTAssertEqual(
            controller.documentModelUIRevision,
            revisionAfterApply,
            "scoped setMix (per-drag hot path) must not bump documentModelUIRevision — bumping it would re-introduce the synchronous mixer layout fan-out / render-livelock"
        )

        // Audio still takes effect: the last send value reached the sample engine.
        XCTAssertEqual(
            sampleEngine.calls.last,
            .setTrackSends(trackID: track.id, sendA: 31.0 / 32.0, sendB: 0)
        )
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
        case setTrackMuteGain(trackID: UUID, muted: Bool)
        case setTrackSceneGain(trackID: UUID, gain: Double)
        case setTrackSends(trackID: UUID, sendA: Double, sendB: Double)
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

    func setTrackMuteGain(trackID: UUID, muted: Bool, source: TrackMuteSource) {
        calls.append(.setTrackMuteGain(trackID: trackID, muted: muted))
    }

    func setTrackSceneGain(trackID: UUID, gain: Double) {
        calls.append(.setTrackSceneGain(trackID: trackID, gain: gain))
    }

    func setTrackSends(trackID: UUID, sendA: Double, sendB: Double) {
        calls.append(.setTrackSends(trackID: trackID, sendA: sendA, sendB: sendB))
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
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {}
    func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? { nil }
}
