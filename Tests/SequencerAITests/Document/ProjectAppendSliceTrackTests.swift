import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAppendSliceTrackTests: XCTestCase {
    func test_appendSliceTrack_createsSampleBackedTrackWithoutUserSlices() {
        var project = Project.empty
        let sampleID = UUID()
        let sample = AudioSample(
            id: sampleID,
            name: "Let There Break",
            fileRef: .appSupportLibrary(relativePath: "Unknown/Let There Break.wav"),
            category: .unknown,
            lengthSeconds: 2.82,
            lengthFrames: 124_362,
            sampleRate: 44_100
        )

        let trackID = project.appendSliceTrack(sample: sample)

        let track = project.tracks.first { $0.id == trackID }
        XCTAssertEqual(track?.name, "Let There Break")
        XCTAssertEqual(track?.trackType, .slice)
        XCTAssertEqual(track?.stepPattern, Array(repeating: false, count: 16))

        guard case let .slicer(sliceSetID, settings) = track?.destination else {
            return XCTFail("expected slicer destination")
        }
        XCTAssertNotEqual(sliceSetID, SliceSet.emptyID)
        XCTAssertEqual(settings, .default)

        let sliceSet = project.sliceSet(id: sliceSetID)
        XCTAssertEqual(sliceSet?.sampleID, sampleID)
        XCTAssertEqual(sliceSet?.userSliceCount, 0)
        XCTAssertEqual(sliceSet?.markers.first?.startFrame, 0)
        XCTAssertEqual(sliceSet?.markers.first?.endFrame, 124_362)
        XCTAssertEqual(sliceSet?.mode, .manual)

        let clipID = project.patternBank(for: trackID).slot(at: 0).sourceRef.clipID
        let clip = project.clipEntry(id: clipID)
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) = clip?.content else {
            return XCTFail("expected a slice trigger clip")
        }
        XCTAssertEqual(stepPattern, Array(repeating: false, count: 16))
        XCTAssertEqual(sliceIndexes, Array(repeating: 0, count: 16))
        XCTAssertEqual(stepModes, Array(repeating: .single, count: 16))
        XCTAssertEqual(stepParameters, Array(repeating: .default, count: 16))
    }
}
