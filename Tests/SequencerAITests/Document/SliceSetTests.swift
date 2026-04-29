import XCTest
@testable import SequencerAI

final class SliceSetTests: XCTestCase {
    func test_emptyPlaceholder_hasDeterministicIDAndNoSample() {
        XCTAssertEqual(SliceSet.empty.id, SliceSet.emptyID)
        XCTAssertNil(SliceSet.empty.sampleID)
        XCTAssertEqual(SliceSet.empty.markers.count, 1)
    }

    func test_normalize_preservesWholeSampleRangeAndSortsUserMarkers() {
        var set = SliceSet(
            sampleID: UUID(),
            markers: [
                SliceMarker(startFrame: 10, endFrame: 20, tag: "all"),
                SliceMarker(startFrame: 80, endFrame: 130, gain: 99, microTimingSteps: 2),
                SliceMarker(startFrame: -10, endFrame: 10),
                SliceMarker(startFrame: 12, endFrame: 18),
                SliceMarker(startFrame: 50, endFrame: 70)
            ],
            mode: .manual
        )

        set.normalize(sampleLengthFrames: 100)

        XCTAssertEqual(set.markers[0].startFrame, 10)
        XCTAssertEqual(set.markers[0].endFrame, 20)
        XCTAssertEqual(set.markers.dropFirst().map(\.startFrame), [12])
        XCTAssertEqual(set.markers.last?.endFrame, 18)
    }

    func test_normalize_clampsUserMarkersAndPreservesPerSliceParameters() {
        var set = SliceSet(
            sampleID: UUID(),
            markers: [
                SliceMarker(startFrame: 0, endFrame: 100),
                SliceMarker(startFrame: 80, endFrame: 130, gain: 99, microTimingSteps: 2),
                SliceMarker(startFrame: -10, endFrame: 10),
                SliceMarker(startFrame: 50, endFrame: 70)
            ],
            mode: .manual
        )

        set.normalize(sampleLengthFrames: 100)

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

    func test_selectionPolicyIgnoresMarkersWhileAnalysisDraftIsVisible() {
        let markerID = UUID()
        let current = SliceSet(
            sampleID: UUID(),
            markers: [
                SliceMarker(startFrame: 0, endFrame: 100),
                SliceMarker(id: markerID, startFrame: 10, endFrame: 20)
            ]
        )
        let draft = SliceSet(
            sampleID: current.sampleID,
            markers: [
                SliceMarker(startFrame: 0, endFrame: 100),
                SliceMarker(id: markerID, startFrame: 30, endFrame: 40),
                SliceMarker(startFrame: 50, endFrame: 60)
            ]
        )

        XCTAssertNil(SliceMarkerSelectionPolicy.assignableMarkerIndex(
            markerID: markerID,
            currentSliceSet: current,
            analysisDraft: draft
        ))
    }

    func test_selectionPolicyUsesCurrentSliceSetWhenNoDraftIsVisible() {
        let markerID = UUID()
        let current = SliceSet(
            sampleID: UUID(),
            markers: [
                SliceMarker(startFrame: 0, endFrame: 100),
                SliceMarker(startFrame: 10, endFrame: 20),
                SliceMarker(id: markerID, startFrame: 20, endFrame: 30)
            ]
        )

        XCTAssertEqual(SliceMarkerSelectionPolicy.assignableMarkerIndex(
            markerID: markerID,
            currentSliceSet: current,
            analysisDraft: nil
        ), 2)
    }

    func test_moveSharedBoundaryUpdatesPreviousEndAndCurrentStart() {
        let markerID = UUID()
        var set = SliceSet(
            sampleID: UUID(),
            markers: [
                SliceMarker(startFrame: 0, endFrame: 100),
                SliceMarker(startFrame: 100, endFrame: 200),
                SliceMarker(id: markerID, startFrame: 200, endFrame: 300),
                SliceMarker(startFrame: 300, endFrame: 400)
            ]
        )

        SliceBoundaryEditing.moveSharedBoundary(
            markerID: markerID,
            to: 240,
            in: &set,
            sampleLengthFrames: 400
        )

        XCTAssertEqual(set.markers[1].endFrame, 240)
        XCTAssertEqual(set.markers[2].startFrame, 240)
    }

    func test_moveSharedBoundaryClampsToKeepAdjacentRegionsNonEmpty() {
        let markerID = UUID()
        var set = SliceSet(
            sampleID: UUID(),
            markers: [
                SliceMarker(startFrame: 0, endFrame: 100),
                SliceMarker(startFrame: 100, endFrame: 200),
                SliceMarker(id: markerID, startFrame: 200, endFrame: 300)
            ]
        )

        SliceBoundaryEditing.moveSharedBoundary(
            markerID: markerID,
            to: 999,
            in: &set,
            sampleLengthFrames: 400
        )

        XCTAssertEqual(set.markers[1].endFrame, 299)
        XCTAssertEqual(set.markers[2].startFrame, 299)
    }
}
