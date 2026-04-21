import Foundation
import XCTest
@testable import SequencerAI

final class ProjectDefaultDestinationForVoiceTagTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try makeCategory("kick")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func test_kick_tag_returns_sample_when_library_has_kick() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)

        let destination = Project.defaultDestination(forVoiceTag: "kick", fallbackPresetName: "test", library: library)

        guard case let .sample(sampleID, _) = destination else {
            return XCTFail("expected .sample for kick tag; got \(destination)")
        }
        XCTAssertEqual(sampleID, library.firstSample(in: .kick)?.id)
    }

    func test_unknown_tag_returns_internal_sampler_fallback() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)

        let destination = Project.defaultDestination(forVoiceTag: "does-not-exist", fallbackPresetName: "808 Kit", library: library)

        guard case let .internalSampler(bankID, preset) = destination else {
            return XCTFail("expected .internalSampler fallback; got \(destination)")
        }
        XCTAssertEqual(bankID, .drumKitDefault)
        XCTAssertEqual(preset, "808 Kit")
    }

    private func makeCategory(_ name: String) throws {
        let directory = libraryRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("\(name)-default.wav"))
    }
}
