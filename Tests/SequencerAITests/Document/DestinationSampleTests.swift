import XCTest
@testable import SequencerAI

final class DestinationSampleTests: XCTestCase {
    func test_sample_codableRoundTrip() throws {
        let id = UUID()
        let d = Destination.sample(sampleID: id, settings: SamplerSettings(gain: -6))
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(Destination.self, from: data)
        XCTAssertEqual(decoded, d)
    }

    func test_sample_kindIsSample() {
        let d = Destination.sample(sampleID: UUID(), settings: .default)
        XCTAssertEqual(d.kind, .sample)
        XCTAssertEqual(d.kindLabel, "Sampler")
    }

    func test_sample_withoutTransientState_returnsSelf() {
        let d = Destination.sample(sampleID: UUID(), settings: .default)
        XCTAssertEqual(d.withoutTransientState, d)
    }

    func test_sample_equality_comparesIDAndSettings() {
        let id = UUID()
        XCTAssertEqual(
            Destination.sample(sampleID: id, settings: SamplerSettings(gain: 0)),
            Destination.sample(sampleID: id, settings: SamplerSettings(gain: 0))
        )
        XCTAssertNotEqual(
            Destination.sample(sampleID: id, settings: SamplerSettings(gain: 0)),
            Destination.sample(sampleID: id, settings: SamplerSettings(gain: -6))
        )
        XCTAssertNotEqual(
            Destination.sample(sampleID: id, settings: .default),
            Destination.sample(sampleID: UUID(), settings: .default)
        )
    }

    func test_sample_summary_mentionsIDPrefix() {
        let id = UUID()
        let d = Destination.sample(sampleID: id, settings: .default)
        XCTAssertTrue(d.summary.contains(String(id.uuidString.prefix(8))))
    }

    func test_legacyDocument_decodesUnchanged() throws {
        let d1 = Destination.midi(port: nil, channel: 0, noteOffset: 0)
        let d2 = Destination.none
        for d in [d1, d2] {
            let data = try JSONEncoder().encode(d)
            let decoded = try JSONDecoder().decode(Destination.self, from: data)
            XCTAssertEqual(decoded, d)
        }
    }
}
