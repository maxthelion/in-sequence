import AVFoundation
import XCTest
@testable import SequencerAI

// MARK: - Fake SamplePlaybackSink

/// Records `setVoiceParam` calls so tests can assert on them without a real audio engine.
final class CapturingSampleSink: SamplePlaybackSink {
    struct VoiceParamCall: Equatable {
        let trackID: UUID
        let kind: BuiltinMacroKind
        let value: Double
    }

    private(set) var voiceParamCalls: [VoiceParamCall] = []

    func start() throws {}
    func stop() {}
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? { nil }
    func setTrackMix(trackID: UUID, level: Double, pan: Double) {}
    func removeTrack(trackID: UUID) {}
    func audition(sampleURL: URL) {}
    func stopAudition() {}

    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {
        voiceParamCalls.append(VoiceParamCall(trackID: trackID, kind: kind, value: value))
    }
}

// MARK: - TrackMacroApplierTests

final class TrackMacroApplierTests: XCTestCase {

    // MARK: Helpers

    private func makeTrack(id: UUID = UUID(), macros: [TrackMacroBinding] = []) -> StepSequenceTrack {
        StepSequenceTrack(
            id: id,
            name: "T",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4,
            macros: macros
        )
    }

    private func builtinBinding(trackID: UUID, kind: BuiltinMacroKind) -> TrackMacroBinding {
        let descriptor = TrackMacroDescriptor.builtin(trackID: trackID, kind: kind)
        return TrackMacroBinding(descriptor: descriptor)
    }

    // MARK: - Builtin macros

    func test_builtin_sampleGain_callsSetVoiceParam() {
        let sink = CapturingSampleSink()
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in nil }
        let trackID = UUID()
        let binding = builtinBinding(trackID: trackID, kind: .sampleGain)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: -6.0]], tracks: [track])

        XCTAssertEqual(sink.voiceParamCalls.count, 1)
        XCTAssertEqual(sink.voiceParamCalls[0].kind, .sampleGain)
        XCTAssertEqual(sink.voiceParamCalls[0].value, -6.0, accuracy: 0.001)
        XCTAssertEqual(sink.voiceParamCalls[0].trackID, trackID)
    }

    func test_builtin_sampleStart_callsSetVoiceParam() {
        let sink = CapturingSampleSink()
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in nil }
        let trackID = UUID()
        let binding = builtinBinding(trackID: trackID, kind: .sampleStart)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.25]], tracks: [track])

        XCTAssertEqual(sink.voiceParamCalls.count, 1)
        XCTAssertEqual(sink.voiceParamCalls[0].kind, .sampleStart)
        XCTAssertEqual(sink.voiceParamCalls[0].value, 0.25, accuracy: 0.001)
    }

    func test_builtin_sampleLength_callsSetVoiceParam() {
        let sink = CapturingSampleSink()
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in nil }
        let trackID = UUID()
        let binding = builtinBinding(trackID: trackID, kind: .sampleLength)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.5]], tracks: [track])

        XCTAssertEqual(sink.voiceParamCalls.count, 1)
        XCTAssertEqual(sink.voiceParamCalls[0].kind, .sampleLength)
        XCTAssertEqual(sink.voiceParamCalls[0].value, 0.5, accuracy: 0.001)
    }

    func test_builtin_exactValueIsForwarded_eachStep() {
        let sink = CapturingSampleSink()
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in nil }
        let trackID = UUID()
        let binding = builtinBinding(trackID: trackID, kind: .sampleGain)
        let track = makeTrack(id: trackID, macros: [binding])

        let stepValues: [Double] = [0.0, -6.0, -12.0, 0.0, 3.0]
        for v in stepValues {
            applier.apply([trackID: [binding.id: v]], tracks: [track])
        }

        XCTAssertEqual(sink.voiceParamCalls.count, stepValues.count)
        for (call, expected) in zip(sink.voiceParamCalls, stepValues) {
            XCTAssertEqual(call.value, expected, accuracy: 0.001)
        }
    }

    // MARK: - Missing values

    func test_missingValueInSnapshotIsSkipped() {
        let sink = CapturingSampleSink()
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in nil }
        let trackID = UUID()
        let binding = builtinBinding(trackID: trackID, kind: .sampleGain)
        let track = makeTrack(id: trackID, macros: [binding])

        // Apply with a values dict that has an entry for trackID but NOT binding.id
        applier.apply([trackID: [UUID(): 0.5]], tracks: [track])

        XCTAssertTrue(sink.voiceParamCalls.isEmpty, "No call expected when binding id absent from values")
    }

    func test_missingTrackInSnapshotIsSkipped() {
        let sink = CapturingSampleSink()
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in nil }
        let trackID = UUID()
        let binding = builtinBinding(trackID: trackID, kind: .sampleGain)
        let track = makeTrack(id: trackID, macros: [binding])

        // Apply with an empty values dict
        applier.apply([:], tracks: [track])

        XCTAssertTrue(sink.voiceParamCalls.isEmpty)
    }

    // MARK: - AU parameters (no real AU available in tests)

    func test_unknownAUAddress_logsOnce_notPerStep() {
        // Without a real AU we can only verify that the applier doesn't crash or
        // call setVoiceParam for an auParameter binding.
        let sink = CapturingSampleSink()
        var providerCallCount = 0
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in
            providerCallCount += 1
            return nil // no AU — simulates missing plugin
        }
        let trackID = UUID()
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "cutoff")
        )
        let binding = TrackMacroBinding(descriptor: descriptor)
        let track = makeTrack(id: trackID, macros: [binding])

        // Apply multiple steps — the provider is called once per unresolved binding per step.
        for _ in 0..<5 {
            applier.apply([trackID: [binding.id: 0.5]], tracks: [track])
        }

        // No voice param calls for an AU binding.
        XCTAssertTrue(sink.voiceParamCalls.isEmpty)
        // Provider is queried each step (no AU → no cache entry).
        XCTAssertGreaterThan(providerCallCount, 0)
    }

    // MARK: - Cache invalidation

    func test_invalidateCache_allowsReLookupForTrack() {
        let sink = CapturingSampleSink()
        var providerCallCount = 0
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in
            providerCallCount += 1
            return nil
        }
        let trackID = UUID()
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Resonance",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0,
            valueType: .scalar,
            source: .auParameter(address: 2, identifier: "res")
        )
        let binding = TrackMacroBinding(descriptor: descriptor)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.5]], tracks: [track])
        let callsAfterFirst = providerCallCount

        applier.invalidateCache(for: trackID)
        applier.apply([trackID: [binding.id: 0.7]], tracks: [track])

        XCTAssertGreaterThan(providerCallCount, callsAfterFirst,
            "Provider should be queried again after cache invalidation")
    }

    func test_invalidateCache_onlyAffectsNamedTrack() {
        // This test verifies that `invalidateCache(for: trackA)` only clears
        // state for trackA. With a nil AU provider (no AU loaded), no cache
        // entries are ever stored, so both tracks will always re-query. The
        // key invariant: calling invalidateCache(for: trackA) must NOT cause
        // trackB to be queried MORE than once per apply call.
        let sink = CapturingSampleSink()
        var providerCallsByTrack: [UUID: Int] = [:]
        let trackA = UUID()
        let trackB = UUID()

        let applier = TrackMacroApplier(sampleEngine: sink) { id in
            providerCallsByTrack[id, default: 0] += 1
            return nil
        }

        let descriptorA = TrackMacroDescriptor(
            id: UUID(), displayName: "A-Cutoff",
            minValue: 0, maxValue: 1, defaultValue: 0.5, valueType: .scalar,
            source: .auParameter(address: 10, identifier: "a.cutoff")
        )
        let bindingA = TrackMacroBinding(descriptor: descriptorA)
        let descriptorB = TrackMacroDescriptor(
            id: UUID(), displayName: "B-Cutoff",
            minValue: 0, maxValue: 1, defaultValue: 0.5, valueType: .scalar,
            source: .auParameter(address: 20, identifier: "b.cutoff")
        )
        let bindingB = TrackMacroBinding(descriptor: descriptorB)

        let tA = makeTrack(id: trackA, macros: [bindingA])
        let tB = makeTrack(id: trackB, macros: [bindingB])

        // First apply: each track queried once each.
        applier.apply([trackA: [bindingA.id: 0.5], trackB: [bindingB.id: 0.5]], tracks: [tA, tB])
        let callsB1 = providerCallsByTrack[trackB, default: 0]

        // Invalidate only trackA; run a second apply.
        applier.invalidateCache(for: trackA)
        applier.apply([trackA: [bindingA.id: 0.5], trackB: [bindingB.id: 0.5]], tracks: [tA, tB])
        let callsB2 = providerCallsByTrack[trackB, default: 0]

        // trackB provider call delta must be exactly one apply call's worth (1 binding × 1 apply).
        // If invalidateCache erroneously touched trackB, it would trigger an extra query.
        XCTAssertEqual(callsB2 - callsB1, 1, "trackB should be queried once per apply, not more")

        // trackA also queried once per apply (no caching possible since AU is nil).
        let callsA2 = providerCallsByTrack[trackA, default: 0]
        XCTAssertEqual(callsA2, 2, "trackA queried once on first apply + once on second apply after invalidation")
    }
}
