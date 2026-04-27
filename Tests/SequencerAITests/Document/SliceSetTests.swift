import XCTest
@testable import SequencerAI

final class SliceSetTests: XCTestCase {
    func test_emptyPlaceholder_hasDeterministicIDAndNoSample() {
        XCTAssertEqual(SliceSet.empty.id, SliceSet.emptyID)
        XCTAssertNil(SliceSet.empty.sampleID)
        XCTAssertEqual(SliceSet.empty.markers.count, 1)
    }

    func test_normalize_rewritesWholeSampleAndSortsUserMarkers() {
        var set = SliceSet(
            sampleID: UUID(),
            markers: [
                SliceMarker(startFrame: 10, endFrame: 20, tag: "all"),
                SliceMarker(startFrame: 80, endFrame: 130, gain: 99, microTimingSteps: 2),
                SliceMarker(startFrame: -10, endFrame: 10),
                SliceMarker(startFrame: 50, endFrame: 70)
            ],
            mode: .manual
        )

        set.normalize(sampleLengthFrames: 100)

        XCTAssertEqual(set.markers[0].startFrame, 0)
        XCTAssertEqual(set.markers[0].endFrame, 100)
        XCTAssertEqual(set.markers.dropFirst().map(\.startFrame), [0, 50, 80])
        XCTAssertEqual(set.markers.last?.endFrame, 100)
        XCTAssertEqual(set.markers.last?.gain, 12)
        XCTAssertEqual(set.markers.last?.microTimingSteps, 0.5)
    }

    func test_markerLookupClampsToAvailableRange() {
        let set = SliceSet(
            sampleID: UUID(),
            markers: [
                SliceMarker(startFrame: 0, endFrame: 100),
                SliceMarker(startFrame: 10, endFrame: 20)
            ]
        )

        XCTAssertEqual(set.marker(at: -1)?.startFrame, 0)
        XCTAssertEqual(set.marker(at: 99)?.startFrame, 10)
    }
}
