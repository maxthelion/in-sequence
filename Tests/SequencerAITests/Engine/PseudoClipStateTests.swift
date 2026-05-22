import XCTest
@testable import SequencerAI

final class PseudoClipStateTests: XCTestCase {
    func test_materialize_fromFullSnapshot_returnsExpectedSelectedRange() throws {
        let trackID = UUID(uuidString: "10000000-0000-0000-0000-000000000010")!
        let snapshot = makeSnapshot(
            maxSteps: 64,
            stepRange: 0..<64,
            emptyStepIndexes: []
        )

        let state = PseudoClipState.materialize(
            sourceTrackID: trackID,
            from: snapshot,
            startStep: 16,
            lengthSteps: 16
        )

        let steps = try XCTUnwrap(state.noteGrid.noteGridSteps)
        XCTAssertEqual(state.sourceTrackID, trackID)
        XCTAssertEqual(state.startStep, 16)
        XCTAssertEqual(state.lengthSteps, 16)
        XCTAssertEqual(steps.count, 16)
        XCTAssertEqual(
            steps.compactMap { $0.main?.notes.first?.pitch },
            Array(76..<92)
        )
    }

    func test_materialize_fromSparseSnapshot_preservesEmptySteps() throws {
        let trackID = UUID(uuidString: "10000000-0000-0000-0000-000000000011")!
        let snapshot = makeSnapshot(
            maxSteps: 64,
            stepRange: 0..<64,
            emptyStepIndexes: [17, 19, 21]
        )

        let state = PseudoClipState.materialize(
            sourceTrackID: trackID,
            from: snapshot,
            startStep: 16,
            lengthSteps: 8
        )

        let steps = try XCTUnwrap(state.noteGrid.noteGridSteps)
        XCTAssertEqual(steps.count, 8)
        XCTAssertEqual(steps[0].main?.notes.map(\.pitch), [76])
        XCTAssertNil(steps[1].main)
        XCTAssertEqual(steps[2].main?.notes.map(\.pitch), [78])
        XCTAssertNil(steps[3].main)
        XCTAssertEqual(steps[4].main?.notes.map(\.pitch), [80])
        XCTAssertNil(steps[5].main)
        XCTAssertEqual(steps[6].main?.notes.map(\.pitch), [82])
        XCTAssertEqual(steps[7].main?.notes.map(\.pitch), [83])
    }

    func test_materialize_fromShortSnapshot_usesFrozenWindowOffsets() throws {
        let trackID = UUID(uuidString: "10000000-0000-0000-0000-000000000012")!
        let snapshot = makeSnapshot(
            maxSteps: 16,
            stepRange: 20..<24,
            emptyStepIndexes: [21]
        )

        let state = PseudoClipState.materialize(
            sourceTrackID: trackID,
            from: snapshot,
            startStep: 12,
            lengthSteps: 4
        )

        let steps = try XCTUnwrap(state.noteGrid.noteGridSteps)
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps[0].main?.notes.map(\.pitch), [80])
        XCTAssertNil(steps[1].main)
        XCTAssertEqual(steps[2].main?.notes.map(\.pitch), [82])
        XCTAssertEqual(steps[3].main?.notes.map(\.pitch), [83])
    }

    func test_materialize_rematerializesCorrectUpdatedRange_whenLengthChanges() {
        let trackID = UUID(uuidString: "10000000-0000-0000-0000-000000000013")!
        let snapshot = makeSnapshot(
            maxSteps: 64,
            stepRange: 0..<64,
            emptyStepIndexes: []
        )

        let halfBarState = PseudoClipState.materialize(
            sourceTrackID: trackID,
            from: snapshot,
            startStep: 8,
            lengthSteps: 8
        )
        let fourBarState = PseudoClipState.materialize(
            sourceTrackID: trackID,
            from: snapshot,
            startStep: 0,
            lengthSteps: 64
        )

        XCTAssertEqual(halfBarState.noteGrid.noteGridLengthSteps, 8)
        XCTAssertEqual(
            halfBarState.noteGrid.noteGridSteps?.compactMap { $0.main?.notes.first?.pitch },
            Array(68..<76)
        )
        XCTAssertEqual(fourBarState.noteGrid.noteGridLengthSteps, 64)
        XCTAssertEqual(fourBarState.noteGrid.noteGridSteps?.first?.main?.notes.map(\.pitch), [60])
        XCTAssertEqual(fourBarState.noteGrid.noteGridSteps?.last?.main?.notes.map(\.pitch), [123])
    }

    func test_supportedLengthSteps_coverV4Choices() {
        XCTAssertEqual(PseudoClipState.supportedLengthSteps, [8, 16, 32, 64])
    }

    private func makeSnapshot(
        maxSteps: Int,
        stepRange: Range<Int>,
        emptyStepIndexes: Set<Int>
    ) -> CaptureSnapshot {
        let steps = stepRange.map { stepIndex in
            CaptureSnapshot.Step(
                absoluteStep: stepIndex,
                notes: emptyStepIndexes.contains(stepIndex)
                    ? []
                    : [CaptureSnapshot.Note(
                        pitch: 60 + stepIndex,
                        velocity: 100,
                        lengthSteps: 2,
                        voiceTag: nil
                    )]
            )
        }

        return CaptureSnapshot(maxSteps: maxSteps, steps: steps)
    }
}
