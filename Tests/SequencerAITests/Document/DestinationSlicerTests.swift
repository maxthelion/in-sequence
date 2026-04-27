import XCTest
@testable import SequencerAI

final class DestinationSlicerTests: XCTestCase {
    func test_slicer_codableRoundTrip() throws {
        let id = UUID()
        let destination = Destination.slicer(
            sliceSetID: id,
            settings: SlicerSettings(gain: -4, transpose: 7, voiceMode: .polyphonic)
        )

        let data = try JSONEncoder().encode(destination)
        let decoded = try JSONDecoder().decode(Destination.self, from: data)

        XCTAssertEqual(decoded, destination)
    }

    func test_slicer_kindAndLabel() {
        let destination = Destination.slicer(sliceSetID: UUID(), settings: .default)

        XCTAssertEqual(destination.kind, .slicer)
        XCTAssertEqual(destination.kindLabel, "Slicer")
    }

    func test_slicer_withoutTransientState_returnsSelf() {
        let destination = Destination.slicer(sliceSetID: UUID(), settings: .default)

        XCTAssertEqual(destination.withoutTransientState, destination)
    }

    func test_slicer_summaryMentionsIDPrefixAndGain() {
        let id = UUID()
        let destination = Destination.slicer(sliceSetID: id, settings: SlicerSettings(gain: -6))

        XCTAssertTrue(destination.summary.contains(String(id.uuidString.prefix(8))))
        XCTAssertTrue(destination.summary.contains("-6.0 dB"))
    }
}
