import XCTest
import AVFoundation
@testable import SequencerAI

/// F2 (consistent mute gating for audio destinations): own-pattern audio is
/// NOT trigger-gated by mute (the per-track gain cuts it), so ROUTED audio must
/// not be trigger-gated either — otherwise the two paths behave differently
/// (a routed voice would stop firing on mute while an own-pattern voice keeps
/// ringing under gain). These tests pin that routed AU / slicer destinations
/// keep receiving events when the DESTINATION track is muted; the mute is a
/// gain on the destination strip, not a gate.
@MainActor
final class EngineControllerRoutedMuteTests: XCTestCase {
    /// Records the events a routed AU destination receives so we can assert the
    /// routed dispatch keeps firing under mute. Only the destination track has
    /// an AU instrument, so the factory hands its sink out first.
    private final class RoutedSinkSpy: TrackPlaybackSink {
        let displayName = "Routed AU"
        var isAvailable = true
        let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
        private(set) var selectedInstrument: AudioInstrumentChoice = .builtInSynth
        var currentAudioUnit: AVAudioUnit? = nil
        private(set) var receivedEvents: [[NoteEvent]] = []
        private(set) var receivedMuteGains: [Bool] = []
        private(set) var receivedMixes: [TrackMixSettings] = []
        func prepareIfNeeded() {}
        func startIfNeeded() {}
        func stop() {}
        func shutdown() {}
        func setMix(_ mix: TrackMixSettings) { receivedMixes.append(mix) }
        func setMuteGain(_ muted: Bool) { receivedMuteGains.append(muted) }
        func setDestination(_ destination: Destination) {
            if case let .auInstrument(componentID, _) = destination {
                selectedInstrument = availableInstruments
                    .first { $0.audioComponentID == componentID } ?? .builtInSynth
            }
        }
        func selectInstrument(_ choice: AudioInstrumentChoice) { selectedInstrument = choice }
        func captureStateBlob() throws -> Data? { nil }
        func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
            receivedEvents.append(noteEvents)
        }
    }

    private func alwaysOnGenerator(id: UUID, pitch: Int) -> GeneratorPoolEntry {
        GeneratorPoolEntry(
            id: id,
            name: "Always On",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0)),
                pitch: .native(.manual(pitches: [pitch], pickMode: .sequential)),
                shape: NoteShape(velocity: 100, gateLength: 4, accent: false)
            )
        )
    }

    /// Routed AU destination keeps receiving events when the destination track
    /// is BOTH mixer-muted AND layer-muted (mute is a gain, not a gate).
    func test_routedAUKeepsFiringWhenDestinationMuted() {
        var createdSinks: [RoutedSinkSpy] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = RoutedSinkSpy()
                createdSinks.append(sink)
                return sink
            }
        )

        // Source track: produces notes, NOT an AU (so it gets no sink). It must
        // NOT be muted — the router gates muted SOURCE tracks at trigger time.
        let sourceGen = alwaysOnGenerator(
            id: UUID(uuidString: "11111111-aaaa-aaaa-aaaa-111111111111")!,
            pitch: 60
        )
        let source = StepSequenceTrack(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Source",
            pitches: [60],
            stepPattern: [true],
            destination: .none,
            velocity: 100,
            gateLength: 4
        )

        // Destination track: an AU instrument, mixer-muted AND layer-muted.
        var dest = StepSequenceTrack(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Dest",
            pitches: [72],
            stepPattern: [false],
            destination: .auInstrument(
                componentID: AudioInstrumentChoice.builtInSynth.audioComponentID,
                stateBlob: nil
            ),
            velocity: 100,
            gateLength: 4
        )
        dest.mix.isMuted = true

        let tracks = [source, dest]
        let generators = [sourceGen]
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let muteLayer = layers.first { $0.target == .mute }!
        var phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: generators,
            clipPool: []
        )
        // Layer-mute the destination too — proving OR of both mute sources still
        // does not gate the routed trigger.
        phrase.setCell(.single(.bool(true)), for: muteLayer.id, trackID: dest.id)

        let route = Route(
            source: .track(source.id),
            destination: .trackInput(dest.id, tag: nil)
        )
        let document = Project(
            version: 1,
            tracks: tracks,
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [route],
            patternBanks: [
                TrackPatternBank(
                    trackID: source.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(sourceGen.id))]
                )
            ],
            selectedTrackID: source.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.start()
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<4 {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.125)
        }
        controller.stop()

        // The destination's AU sink is the only one created.
        guard let destSink = createdSinks.first else {
            return XCTFail("destination AU sink should have been created")
        }
        let routedNotes = destSink.receivedEvents.flatMap { $0 }
        XCTAssertGreaterThan(
            routedNotes.count, 0,
            "routed AU must keep firing into a muted destination — mute is a gain, not a trigger-gate"
        )
        // And the mute reached the destination as a GAIN change (the cut path).
        XCTAssertTrue(
            destSink.receivedMuteGains.contains(true) || destSink.receivedMixes.contains { $0.isMuted },
            "destination mute must be applied as a gain on the destination strip"
        )
    }
}
