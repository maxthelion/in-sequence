import XCTest
@testable import SequencerAI

final class StyleProfilesTests: XCTestCase {
    func test_style_profile_id_has_3_cases() {
        XCTAssertEqual(StyleProfileID.allCases.count, 3)
    }

    func test_every_style_profile_id_has_a_profile() {
        for id in StyleProfileID.allCases {
            XCTAssertNotNil(StyleProfile.for(id: id), "Missing style profile for \(id)")
        }
    }

    func test_distance_weights_have_expected_shape() {
        for id in StyleProfileID.allCases {
            guard let profile = StyleProfile.for(id: id) else {
                XCTFail("Missing style profile for \(id)")
                continue
            }

            XCTAssertEqual(profile.distanceWeights.count, 8)

            let sum = profile.distanceWeights.reduce(0, +)
            XCTAssertGreaterThanOrEqual(sum, 0.8, "Style profile \(id) has unexpectedly low total weight")
            XCTAssertLessThanOrEqual(sum, 1.2, "Style profile \(id) has unexpectedly high total weight")
        }
    }

    func test_jazz_tolerates_leaps_more_than_vocal() {
        XCTAssertGreaterThan(
            StyleProfile.for(id: .jazz)?.leapPenalty ?? 0,
            StyleProfile.for(id: .vocal)?.leapPenalty ?? 0
        )
    }
}
