import XCTest
@testable import SequencerAI

final class ScalesTests: XCTestCase {
    func test_scale_id_has_19_cases() {
        XCTAssertEqual(ScaleID.allCases.count, 19)
    }

    func test_every_scale_id_has_a_scale() {
        for id in ScaleID.allCases {
            XCTAssertNotNil(Scale.for(id: id), "Missing scale for \(id)")
        }
    }

    func test_spot_check_intervals() {
        XCTAssertEqual(Scale.for(id: .major)?.intervals, [0, 2, 4, 5, 7, 9, 11])
        XCTAssertEqual(Scale.for(id: .chromatic)?.intervals.count, 12)
        XCTAssertEqual(Scale.for(id: .majorPentatonic)?.intervals.count, 5)
        XCTAssertEqual(Scale.for(id: .minorPentatonic)?.intervals.count, 5)
    }

    func test_scale_intervals_are_valid() {
        for id in ScaleID.allCases {
            guard let scale = Scale.for(id: id) else {
                XCTFail("Missing scale for \(id)")
                continue
            }

            XCTAssertEqual(scale.intervals.first, 0, "Scale \(id) should start at 0")
            XCTAssertTrue(scale.intervals.allSatisfy { (0..<12).contains($0) }, "Scale \(id) has interval outside octave")
            XCTAssertEqual(scale.intervals, scale.intervals.sorted(), "Scale \(id) should be ascending")
            XCTAssertEqual(scale.intervals.count, Set(scale.intervals).count, "Scale \(id) should not repeat intervals")
        }
    }
}
