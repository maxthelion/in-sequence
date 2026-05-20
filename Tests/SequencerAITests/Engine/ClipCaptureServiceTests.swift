import XCTest
@testable import SequencerAI

final class ClipCaptureServiceTests: XCTestCase {
    func test_append_replacesPreviousNotesForSameStep() {
        let trackID = UUID()
        var service = ClipCaptureService()

        service.append(trackID: trackID, stepIndex: 4, notes: [note(pitch: 60)])
        service.append(trackID: trackID, stepIndex: 4, notes: [note(pitch: 64)])

        let steps = noteGridSteps(in: service.capturedClipContent(trackID: trackID, lengthSteps: 1))
        XCTAssertEqual(steps?.count, 1)
        XCTAssertEqual(steps?[0].main?.notes.map(\.pitch), [64])
    }

    func test_append_trimsToMaximumLength() {
        let trackID = UUID()
        var service = ClipCaptureService(maxSteps: 2)

        service.append(trackID: trackID, stepIndex: 0, notes: [note(pitch: 60)])
        service.append(trackID: trackID, stepIndex: 1, notes: [note(pitch: 61)])
        service.append(trackID: trackID, stepIndex: 2, notes: [note(pitch: 62)])

        let steps = noteGridSteps(in: service.capturedClipContent(trackID: trackID))
        XCTAssertEqual(steps?.count, 2)
        XCTAssertEqual(steps?.compactMap { $0.main?.notes.first?.pitch }, [61, 62])
    }

    func test_capturedClipContent_returnsNilWhenTrackHasNoCapture() {
        let service = ClipCaptureService()

        XCTAssertNil(service.capturedClipContent(trackID: UUID()))
    }

    func test_capturedClipContent_padsExplicitLengthAndClampsNoteLength() {
        let trackID = UUID()
        var service = ClipCaptureService()

        service.append(trackID: trackID, stepIndex: 8, notes: [note(pitch: 70, velocity: 96, length: 0)])

        guard case let .noteGrid(lengthSteps, steps) = service.capturedClipContent(trackID: trackID, lengthSteps: 3) else {
            return XCTFail("expected note-grid capture")
        }

        XCTAssertEqual(lengthSteps, 3)
        XCTAssertEqual(steps.count, 3)
        XCTAssertNil(steps[0].main)
        XCTAssertNil(steps[1].main)
        XCTAssertEqual(steps[2].main?.notes.map(\.pitch), [70])
        XCTAssertEqual(steps[2].main?.notes.map(\.velocity), [96])
        XCTAssertEqual(steps[2].main?.notes.map(\.lengthSteps), [1])
    }

    func test_removeMissingTracks_prunesCaptureBuffersForRemovedTracks() {
        let keptTrackID = UUID()
        let removedTrackID = UUID()
        var service = ClipCaptureService()

        service.append(trackID: keptTrackID, stepIndex: 0, notes: [note(pitch: 60)])
        service.append(trackID: removedTrackID, stepIndex: 0, notes: [note(pitch: 72)])

        service.removeMissingTracks([keptTrackID])

        XCTAssertNotNil(service.capturedClipContent(trackID: keptTrackID))
        XCTAssertNil(service.capturedClipContent(trackID: removedTrackID))
    }

    private func note(pitch: Int, velocity: Int = 100, length: Int = 2) -> GeneratedNote {
        GeneratedNote(
            pitch: pitch,
            velocity: velocity,
            length: length,
            voiceTag: nil
        )
    }

    private func noteGridSteps(in content: ClipContent?) -> [ClipStep]? {
        guard case let .noteGrid(_, steps) = content else {
            return nil
        }
        return steps
    }
}
