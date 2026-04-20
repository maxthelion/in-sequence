import XCTest
@testable import SequencerAI

final class StepAlgoKindTests: XCTestCase {
    func test_step_algo_kind_projection_matches_cases() {
        XCTAssertEqual(StepAlgo.manual(pattern: [true, false]).kind, .manual)
        XCTAssertEqual(StepAlgo.euclidean(pulses: 3, steps: 8, offset: 1).kind, .euclidean)
        XCTAssertEqual(StepAlgo.randomWeighted(density: 0.4).kind, .randomWeighted)
        XCTAssertEqual(StepAlgo.perStepProbability(probs: [0.2, 0.8]).kind, .perStepProbability)
        XCTAssertEqual(StepAlgo.fromClipSteps(clipID: UUID()).kind, .fromClipSteps)
    }

    func test_default_algo_round_trips_to_same_kind() {
        let clipChoices = [ClipPoolEntry.defaultPool[0]]
        let current = StepAlgo.manual(pattern: Array(repeating: false, count: 16))

        for kind in StepAlgoKind.allCases {
            XCTAssertEqual(kind.defaultAlgo(clipChoices: clipChoices, current: current).kind, kind)
        }
    }
}
