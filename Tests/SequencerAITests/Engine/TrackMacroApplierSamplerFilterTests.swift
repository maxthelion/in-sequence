import AVFoundation
import XCTest
@testable import SequencerAI

// MARK: - Spy filter node

/// A `SamplerFilterNode` subclass that records setter calls.
///
/// We can't mock `SamplerFilterNode` directly since it's a final class, so this
/// spy wraps a `CapturingFilterSink` (a simple call-recorder) rather than
/// inheriting — the applier calls via `SamplePlaybackSink.filterNode(for:)`,
/// so we inject the spy through a custom sink.
private final class CapturingFilterSink: SamplePlaybackSink {

    // MARK: - Filter call records

    struct SetCutoffCall: Equatable { let trackID: UUID; let hz: Double }
    struct SetResoCall: Equatable { let trackID: UUID; let value: Double }
    struct SetDriveCall: Equatable { let trackID: UUID; let value: Double }
    struct SetTypeCall: Equatable { let trackID: UUID; let type: SamplerFilterType }
    struct SetPolesCall: Equatable { let trackID: UUID; let poles: SamplerFilterPoles }

    private(set) var cutoffCalls: [SetCutoffCall] = []
    private(set) var resoCalls: [SetResoCall] = []
    private(set) var driveCalls: [SetDriveCall] = []
    private(set) var typeCalls: [SetTypeCall] = []
    private(set) var polesCalls: [SetPolesCall] = []

    // MARK: - Spy filter node (records calls)

    /// A per-track spy node that writes back to this sink's call arrays.
    private final class SpyFilterNode: SamplerFilterNode {
        unowned let owner: CapturingFilterSink
        let trackID: UUID

        init(owner: CapturingFilterSink, trackID: UUID) {
            self.owner = owner
            self.trackID = trackID
            super.init()
        }

        override func setCutoff(hz: Double) {
            owner.cutoffCalls.append(.init(trackID: trackID, hz: hz))
            super.setCutoff(hz: hz)
        }
        override func setResonance(_ n: Double) {
            owner.resoCalls.append(.init(trackID: trackID, value: n))
            super.setResonance(n)
        }
        override func setDrive(_ n: Double) {
            owner.driveCalls.append(.init(trackID: trackID, value: n))
            super.setDrive(n)
        }
        override func setType(_ type: SamplerFilterType) {
            owner.typeCalls.append(.init(trackID: trackID, type: type))
            super.setType(type)
        }
        override func setPoles(_ poles: SamplerFilterPoles) {
            owner.polesCalls.append(.init(trackID: trackID, poles: poles))
            super.setPoles(poles)
        }
    }

    private var filterNodes: [UUID: SamplerFilterNode] = [:]

    func getOrMakeFilter(trackID: UUID) -> SamplerFilterNode {
        if let existing = filterNodes[trackID] { return existing }
        let node = SpyFilterNode(owner: self, trackID: trackID)
        filterNodes[trackID] = node
        return node
    }

    // MARK: - SamplePlaybackSink conformance

    private(set) var voiceParamCalls: [(UUID, BuiltinMacroKind, Double)] = []

    func start() throws {}
    func stop() {}
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? { nil }
    func setTrackMix(trackID: UUID, level: Double, pan: Double) {}
    func removeTrack(trackID: UUID) {}
    func audition(sampleURL: URL) {}
    func stopAudition() {}
    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {
        voiceParamCalls.append((trackID, kind, value))
    }
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {}
    func filterNode(for trackID: UUID) -> SamplerFilterNode? {
        filterNodes[trackID]
    }
}

// MARK: - TrackMacroApplierSamplerFilterTests

final class TrackMacroApplierSamplerFilterTests: XCTestCase {

    // MARK: - Helpers

    private func makeTrack(id: UUID = UUID(), macros: [TrackMacroBinding]) -> StepSequenceTrack {
        StepSequenceTrack(id: id, name: "T", pitches: [60], stepPattern: [true], velocity: 100, gateLength: 4, macros: macros)
    }

    private func builtinBinding(trackID: UUID, kind: BuiltinMacroKind) -> TrackMacroBinding {
        TrackMacroBinding(descriptor: TrackMacroDescriptor.builtin(trackID: trackID, kind: kind))
    }

    private func makeSinkAndApplier() -> (CapturingFilterSink, TrackMacroApplier) {
        let sink = CapturingFilterSink()
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in nil }
        return (sink, applier)
    }

    // MARK: - Cutoff dispatch

    func test_cutoff_macro_callsSetCutoff() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        _ = sink.getOrMakeFilter(trackID: trackID)  // pre-create the spy node
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterCutoff)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 1200]], tracks: [track])

        XCTAssertEqual(sink.cutoffCalls.count, 1)
        XCTAssertEqual(sink.cutoffCalls[0].hz, 1200, accuracy: 0.001)
        XCTAssertEqual(sink.cutoffCalls[0].trackID, trackID)
    }

    // MARK: - Resonance dispatch

    func test_reso_macro_callsSetResonance() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        _ = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterReso)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.7]], tracks: [track])

        XCTAssertEqual(sink.resoCalls.count, 1)
        XCTAssertEqual(sink.resoCalls[0].value, 0.7, accuracy: 0.001)
    }

    // MARK: - Drive dispatch

    func test_drive_macro_callsSetDrive() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        _ = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterDrive)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.5]], tracks: [track])

        XCTAssertEqual(sink.driveCalls.count, 1)
        XCTAssertEqual(sink.driveCalls[0].value, 0.5, accuracy: 0.001)
    }

    // MARK: - Type dispatch

    func test_type_macro_2point0_callsSetTypeBandpass() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        _ = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterType)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 2.0]], tracks: [track])

        XCTAssertEqual(sink.typeCalls.count, 1)
        XCTAssertEqual(sink.typeCalls[0].type, .bandpass)
    }

    func test_type_macro_negativeMinus1_clampsToLowpass() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        _ = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterType)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: -1]], tracks: [track])

        XCTAssertEqual(sink.typeCalls.count, 1)
        XCTAssertEqual(sink.typeCalls[0].type, SamplerFilterType.allCases[0])
    }

    func test_type_macro_99_clampsToLastCase() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        _ = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterType)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 99]], tracks: [track])

        XCTAssertEqual(sink.typeCalls.count, 1)
        XCTAssertEqual(sink.typeCalls[0].type, SamplerFilterType.allCases.last!)
    }

    // MARK: - Poles dispatch

    func test_poles_macro_0point4_roundsToZero_setsPolesToOne() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        _ = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterPoles)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.4]], tracks: [track])

        XCTAssertEqual(sink.polesCalls.count, 1)
        XCTAssertEqual(sink.polesCalls[0].poles, SamplerFilterPoles.allCases[0])
    }

    // MARK: - Missing filter node: skip silently

    func test_filterMacro_noFilterNode_skippedSilently() {
        let sink = CapturingFilterSink()
        // Do NOT pre-create the filter node for this track.
        let applier = TrackMacroApplier(sampleEngine: sink) { _ in nil }
        let trackID = UUID()
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterCutoff)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 1200]], tracks: [track])

        // No crash; no calls.
        XCTAssertTrue(sink.cutoffCalls.isEmpty)
    }
}
