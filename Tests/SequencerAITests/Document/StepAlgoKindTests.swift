import XCTest
@testable import SequencerAI

final class StepAlgoKindTests: XCTestCase {
    func test_step_algo_kind_projection_matches_cases() {
        XCTAssertEqual(StepAlgo.euclidean(pulses: 3, steps: 8, offset: 1).kind, .euclidean)
    }

    func test_default_algo_round_trips_to_same_kind() {
        let current = StepAlgo.euclidean(pulses: 5, steps: 16, offset: 2)

        for kind in StepAlgoKind.allCases {
            XCTAssertEqual(kind.defaultAlgo(current: current).kind, kind)
        }
    }
}
