import AVFoundation
import XCTest
@testable import SequencerAI

// MARK: - Filter sink

/// A `SamplePlaybackSink` test double that owns real `SamplerFilterNode`
/// instances so tests can assert against the node state after macro dispatch.
private final class CapturingFilterSink: SamplePlaybackSink {

    private var filterNodes: [UUID: SamplerFilterNode] = [:]

    func getOrMakeFilter(trackID: UUID) -> SamplerFilterNode {
        if let existing = filterNodes[trackID] { return existing }
        let node = SamplerFilterNode()
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

@MainActor
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
        let node = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterCutoff)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 1200]], tracks: [track])

        XCTAssertEqual(node.currentSettings.cutoffHz, 1200, accuracy: 0.001)
    }

    // MARK: - Resonance dispatch

    func test_reso_macro_callsSetResonance() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        let node = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterReso)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.7]], tracks: [track])

        XCTAssertEqual(node.currentSettings.resonance, 0.7, accuracy: 0.001)
    }

    // MARK: - Drive dispatch

    func test_drive_macro_callsSetDrive() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        let node = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterDrive)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.5]], tracks: [track])

        XCTAssertEqual(node.currentSettings.drive, 0.5, accuracy: 0.001)
    }

    // MARK: - Type dispatch

    func test_type_macro_2point0_callsSetTypeBandpass() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        let node = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterType)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 2.0]], tracks: [track])

        XCTAssertEqual(node.currentSettings.type, .bandpass)
    }

    func test_type_macro_negativeMinus1_clampsToLowpass() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        let node = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterType)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: -1]], tracks: [track])

        XCTAssertEqual(node.currentSettings.type, .lowpass)
    }

    func test_type_macro_99_clampsToLastCase() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        let node = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterType)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 99]], tracks: [track])

        XCTAssertEqual(node.currentSettings.type, .notch)
    }

    // MARK: - Poles dispatch

    func test_poles_macro_0point4_roundsToZero_setsPolesToOne() {
        let (sink, applier) = makeSinkAndApplier()
        let trackID = UUID()
        let node = sink.getOrMakeFilter(trackID: trackID)
        let binding = builtinBinding(trackID: trackID, kind: .samplerFilterPoles)
        let track = makeTrack(id: trackID, macros: [binding])

        applier.apply([trackID: [binding.id: 0.4]], tracks: [track])

        XCTAssertEqual(node.currentSettings.poles, .one)
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

        XCTAssertNil(sink.filterNode(for: trackID))
    }
}
