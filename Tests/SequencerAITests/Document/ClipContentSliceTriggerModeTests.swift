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

    func test_sliceTriggerStepsCollectsParallelArraysIntoPerStepValues() {
        let parameters = SliceTriggerStepParameters(gain: 3)
        let steps = SliceTriggerSteps(
            stepPattern: [true, false, true],
            sliceIndexes: [2],
            stepModes: [.runFromHere],
            stepParameters: [parameters],
            defaultSliceIndex: 1
        )

        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps[0], SliceTriggerStep(isOn: true, sliceIndex: 2, mode: .runFromHere, parameters: parameters))
        XCTAssertEqual(steps[1], SliceTriggerStep(isOn: false, sliceIndex: 1, mode: .single, parameters: .default))
        XCTAssertEqual(steps[2], SliceTriggerStep(isOn: true, sliceIndex: 1, mode: .single, parameters: .default))
    }

    func test_sliceTriggerStepsMutationsExportParallelArraysForExistingStorage() {
        var steps = SliceTriggerSteps(
            stepPattern: [false, false],
            sliceIndexes: [0, 0],
            stepModes: [],
            stepParameters: [],
            defaultSliceIndex: 1
        )

        steps.toggleStep(at: 0, defaultSliceIndex: 1, selectedSliceIndex: 3)
        steps.assignMode(.runFromHere, at: 0)
        steps.assignParameters(SliceTriggerStepParameters(gain: 4, pitch: 2), at: 0)
        steps.assignSliceIndex(5, at: 1)

        XCTAssertEqual(steps.stepPattern, [true, true])
        XCTAssertEqual(steps.sliceIndexes, [3, 5])
        XCTAssertEqual(steps.stepModes, [.runFromHere, .single])
        XCTAssertEqual(steps.stepParameters[0], SliceTriggerStepParameters(gain: 4, pitch: 2))
        XCTAssertEqual(steps.stepParameters[1], .default)
    }
}
