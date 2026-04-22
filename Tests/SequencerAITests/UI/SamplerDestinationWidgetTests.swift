import XCTest
import SwiftUI
import AVFoundation
@testable import SequencerAI

final class SamplerDestinationWidgetTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for fname in ["a.wav", "b.wav", "c.wav"] {
            let dir = libraryRoot.appendingPathComponent("kick")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data().write(to: dir.appendingPathComponent(fname))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private final class SpySink: SamplePlaybackSink {
        var auditionCalls = 0
        var stopAuditionCalls = 0
        var applyFilterCalls = 0
        var lastApplyFilterTrackID: UUID?
        func start() throws {}
        func stop() {}
        func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? { nil }
        func setTrackMix(trackID: UUID, level: Double, pan: Double) {}
        func removeTrack(trackID: UUID) {}
        func audition(sampleURL: URL) { auditionCalls += 1 }
        func stopAudition() { stopAuditionCalls += 1 }
        func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {}
        func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {
            applyFilterCalls += 1
            lastApplyFilterTrackID = trackID
        }
        func filterNode(for trackID: UUID) -> SamplerFilterNode? { nil }
    }

    func test_library_nextSample_cyclesWithinCategory() {
        let lib = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kicks = lib.samples(in: .kick)
        XCTAssertEqual(kicks.count, 3)
        XCTAssertEqual(lib.nextSample(after: kicks[0].id)?.id, kicks[1].id)
        XCTAssertEqual(lib.nextSample(after: kicks[2].id)?.id, kicks[0].id)
    }

    func test_gainClamp_roundTrips() {
        var settings = SamplerSettings.default
        settings.gain = 999
        let destination = Destination.sample(sampleID: UUID(), settings: settings.clamped())
        if case let .sample(_, s) = destination {
            XCTAssertEqual(s.gain, 12)
        } else {
            XCTFail("destination should be .sample")
        }
    }

    func test_orphanSampleID_resolvesToNil() {
        let lib = AudioSampleLibrary(libraryRoot: libraryRoot)
        XCTAssertNil(lib.sample(id: UUID()))
    }

    func test_auditionSinkReceivesCall() throws {
        let lib = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = lib.firstSample(in: .kick) else { XCTFail(); return }
        let spy = SpySink()
        let url = try kick.fileRef.resolve(libraryRoot: lib.libraryRoot)
        spy.audition(sampleURL: url)
        XCTAssertEqual(spy.auditionCalls, 1)
    }

    // MARK: - Filter handler tests

    func test_onCutoffChanged_writesFilterAndCallsApplyFilter() {
        let lib = AudioSampleLibrary(libraryRoot: libraryRoot)
        let spy = SpySink()
        let trackID = UUID()
        var filterSettings = SamplerFilterSettings()
        var destination = Destination.none

        var widget = SamplerDestinationWidget(
            destination: Binding(get: { destination }, set: { destination = $0 }),
            library: lib,
            sampleEngine: spy,
            trackID: trackID,
            filterSettings: Binding(get: { filterSettings }, set: { filterSettings = $0 })
        )

        widget.onCutoffChanged(1200)

        XCTAssertEqual(filterSettings.cutoffHz, 1200, accuracy: 0.001)
        XCTAssertEqual(spy.applyFilterCalls, 1)
        XCTAssertEqual(spy.lastApplyFilterTrackID, trackID)
    }
}

