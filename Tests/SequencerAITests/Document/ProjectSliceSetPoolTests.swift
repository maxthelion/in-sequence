import XCTest
@testable import SequencerAI

final class ProjectSliceSetPoolTests: XCTestCase {
    func test_addAndLookupSliceSet() throws {
        var project = Project.empty
        let sampleID = UUID()
        let set = SliceSet(
            sampleID: sampleID,
            markers: [SliceMarker(startFrame: 0, endFrame: 100)]
        )

        project.addSliceSet(set)

        XCTAssertEqual(project.sliceSet(id: set.id), set)
        XCTAssertEqual(project.firstSliceSet(for: sampleID), set)
    }

    func test_emptySliceSetLookupReturnsPlaceholderWithoutStoringIt() {
        let project = Project.empty

        XCTAssertEqual(project.sliceSet(id: SliceSet.emptyID), .empty)
        XCTAssertTrue(project.sliceSetPool.isEmpty)
    }

    func test_removeSliceSetResetsReferencingTrackToEmptySlicer() {
        let setID = UUID()
        var track = StepSequenceTrack.default
        track.destination = .slicer(sliceSetID: setID, settings: SlicerSettings(gain: -3))
        var project = Project(
            version: 1,
            tracks: [track],
            clipPool: [],
            patternBanks: [],
            sliceSetPool: [
                SliceSet(id: setID, sampleID: UUID(), markers: [SliceMarker(startFrame: 0, endFrame: 100)])
            ],
            selectedTrackID: track.id,
            phrases: [],
            selectedPhraseID: UUID()
        )

        project.removeSliceSet(id: setID)

        XCTAssertTrue(project.sliceSetPool.isEmpty)
        XCTAssertEqual(project.tracks.first?.destination, .slicer(sliceSetID: SliceSet.emptyID, settings: .default))
    }

    func test_legacyProjectDecodeDefaultsSliceSetPoolToEmpty() throws {
        var project = Project.empty
        project.sliceSetPool = [
            SliceSet(sampleID: UUID(), markers: [SliceMarker(startFrame: 0, endFrame: 100)])
        ]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as! [String: Any]
        json.removeValue(forKey: "sliceSetPool")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Project.self, from: legacyData)

        XCTAssertTrue(decoded.sliceSetPool.isEmpty)
    }
}
