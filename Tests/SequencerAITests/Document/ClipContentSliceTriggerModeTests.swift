import XCTest
@testable import SequencerAI

final class ClipContentSliceTriggerModeTests: XCTestCase {
    func test_normalizedPadsSliceStepModesToStepCount() {
        let content = ClipContent.sliceTriggers(
            stepPattern: [true, false, true],
            sliceIndexes: [0, 1],
            stepModes: [.runFromHere]
        ).normalized

        guard case let .sliceTriggers(_, _, modes, _) = content else {
            return XCTFail("expected slice trigger content")
        }
        XCTAssertEqual(modes, [.runFromHere, .single, .single])
    }

    func test_codableRoundTripPreservesRunFromHereMode() throws {
        let content = ClipContent.sliceTriggers(
            stepPattern: [true],
            sliceIndexes: [2],
            stepModes: [.runFromHere]
        ).normalized

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

        guard case let .sliceTriggers(_, _, modes, _) = decoded else {
            return XCTFail("expected slice trigger content")
        }
        XCTAssertEqual(modes, [.single, .single])
    }

    func test_normalizedPadsSliceStepParametersToStepCount() {
        let parameters = SliceTriggerStepParameters(gain: 3, pitch: 2, startTrim: 0.1)
        let content = ClipContent.sliceTriggers(
            stepPattern: [true, false, true],
            sliceIndexes: [0, 1],
            stepModes: [.runFromHere],
            stepParameters: [parameters]
        ).normalized

        guard case let .sliceTriggers(_, _, _, stepParameters) = content else {
            return XCTFail("expected slice trigger content")
        }
        XCTAssertEqual(stepParameters, [parameters, .default, .default])
    }

    func test_legacySliceTriggerDecodeDefaultsParameters() throws {
        let legacyJSON = """
        {
          "sliceTriggers": {
            "stepPattern": [true, false],
            "sliceIndexes": [0],
            "stepModes": ["runFromHere"]
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ClipContent.self, from: legacyJSON).normalized

        guard case let .sliceTriggers(_, _, _, parameters) = decoded else {
            return XCTFail("expected slice trigger content")
        }
        XCTAssertEqual(parameters, [.default, .default])
    }
}
