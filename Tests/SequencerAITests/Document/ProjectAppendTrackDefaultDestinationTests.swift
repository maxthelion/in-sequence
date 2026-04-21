import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAppendTrackDefaultDestinationTests: XCTestCase {
    func test_appendTrack_monoMelodic_defaults_to_none() {
        var project = Project.empty

        project.appendTrack(trackType: .monoMelodic)

        XCTAssertEqual(project.selectedTrack.destination, .none)
    }

    func test_appendTrack_polyMelodic_defaults_to_none() {
        var project = Project.empty

        project.appendTrack(trackType: .polyMelodic)

        XCTAssertEqual(project.selectedTrack.destination, .none)
    }

    func test_appendTrack_slice_defaults_to_internalSampler() {
        var project = Project.empty

        project.appendTrack(trackType: .slice)

        guard case let .internalSampler(bankID, preset) = project.selectedTrack.destination else {
            return XCTFail("expected .internalSampler default for slice track; got \(project.selectedTrack.destination)")
        }
        XCTAssertEqual(bankID, .sliceDefault)
        XCTAssertEqual(preset, "empty-slice")
    }
}
