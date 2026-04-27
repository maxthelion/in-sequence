import XCTest
@testable import SequencerAI

final class ClipContentSliceTriggerModeTests: XCTestCase {
    func test_normalizedPadsSliceStepModesToStepCount() {
        let content = ClipContent.sliceTriggers(
            stepPattern: [true, false, true],
            sliceIndexes: [0, 1],
            stepModes: [.runFromHere]
        ).normalized

        guard case let .sliceTriggers(_, _, modes) = content else {
            return XCTFail("expected slice trigger content")
        }
        XCTAssertEqual(modes, [.runFromHere, .single, .single])
    }

    func test_codableRoundTripPreservesRunFromHereMode() throws {
        let content = ClipContent.sliceTriggers(
            stepPattern: [true],
            sliceIndexes: [2],
            stepModes: [.runFromHere]
        )

        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ClipContent.self, from: data)

        XCTAssertEqual(decoded, content)
    }

    func test_legacySliceTriggerDecodeDefaultsModesToSingle() throws {
        let legacyJSON = """
        {
          "sliceTriggers": {
            "stepPattern": [true, false],
            "sliceIndexes": [0]
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ClipContent.self, from: legacyJSON).normalized

        guard case let .sliceTriggers(_, _, modes) = decoded else {
            return XCTFail("expected slice trigger content")
        }
        XCTAssertEqual(modes, [.single, .single])
    }
}
