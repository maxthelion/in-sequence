import XCTest
@testable import SequencerAI

final class ClipContentEmptyTests: XCTestCase {
    func test_stepSequence_allFalse_isEmpty() {
        let content = ClipContent.stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: [60])
        XCTAssertTrue(clipIsEmpty(content))
    }

    func test_stepSequence_anyTrue_isNotEmpty() {
        var pattern = Array(repeating: false, count: 16)
        pattern[3] = true
        let content = ClipContent.stepSequence(stepPattern: pattern, pitches: [60])
        XCTAssertFalse(clipIsEmpty(content))
    }

    func test_sliceTriggers_allFalse_isEmpty() {
        let content = ClipContent.sliceTriggers(stepPattern: Array(repeating: false, count: 16), sliceIndexes: [])
        XCTAssertTrue(clipIsEmpty(content))
    }

    func test_sliceTriggers_anyTrue_isNotEmpty() {
        var pattern = Array(repeating: false, count: 16)
        pattern[0] = true
        let content = ClipContent.sliceTriggers(stepPattern: pattern, sliceIndexes: [0])
        XCTAssertFalse(clipIsEmpty(content))
    }

    func test_pianoRoll_emptyNotes_isEmpty() {
        let content = ClipContent.pianoRoll(lengthBars: 1, stepsPerBar: 16, notes: [])
        XCTAssertTrue(clipIsEmpty(content))
    }

    func test_pianoRoll_withNote_isNotEmpty() {
        let content = ClipContent.pianoRoll(
            lengthBars: 1,
            stepsPerBar: 16,
            notes: [ClipNote(pitch: 60, startStep: 0, lengthSteps: 1, velocity: 100)]
        )
        XCTAssertFalse(clipIsEmpty(content))
    }
}
