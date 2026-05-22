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

    func test_defaultCaptureWindow_retainsMostRecent256Steps() {
        let trackID = UUID()
        var service = ClipCaptureService()

        for step in 0..<300 {
            service.append(trackID: trackID, stepIndex: step, notes: [note(pitch: step)])
        }

        let snapshot = service.captureSnapshot(trackID: trackID)
        XCTAssertEqual(snapshot.maxSteps, 256)
        XCTAssertEqual(snapshot.steps.count, 256)
        XCTAssertEqual(snapshot.steps.first?.absoluteStep, 44)
        XCTAssertEqual(snapshot.steps.last?.absoluteStep, 299)
        XCTAssertEqual(snapshot.steps.first?.notes.map(\.pitch), [44])
        XCTAssertEqual(snapshot.steps.last?.notes.map(\.pitch), [299])
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

    func test_captureSnapshot_returnsStableCopiedNotes() {
        let trackID = UUID()
        var service = ClipCaptureService(maxSteps: 4)

        service.append(trackID: trackID, stepIndex: 10, notes: [
            note(pitch: 60, velocity: 80, length: 0, voiceTag: "kick")
        ])
        let snapshot = service.captureSnapshot(trackID: trackID)

        service.append(trackID: trackID, stepIndex: 10, notes: [note(pitch: 72, velocity: 110)])
        service.append(trackID: trackID, stepIndex: 11, notes: [note(pitch: 73)])

        XCTAssertEqual(snapshot.steps.count, 1)
        XCTAssertEqual(snapshot.steps[0].absoluteStep, 10)
        XCTAssertEqual(snapshot.steps[0].notes, [
            CaptureSnapshot.Note(
                pitch: 60,
                velocity: 80,
                lengthSteps: 1,
                voiceTag: "kick"
            )
        ])
    }

    func test_captureSnapshot_returnsEmptySnapshotWhenTrackHasNoHistory() {
        let service = ClipCaptureService(maxSteps: 16)

        let snapshot = service.captureSnapshot(trackID: UUID())

        XCTAssertEqual(snapshot.maxSteps, 16)
        XCTAssertTrue(snapshot.isEmpty)
    }

    func test_captureSnapshot_returnsPartialSnapshotForShortHistory() {
        let trackID = UUID()
        var service = ClipCaptureService(maxSteps: 16)

        service.append(trackID: trackID, stepIndex: 7, notes: [])
        service.append(trackID: trackID, stepIndex: 8, notes: [note(pitch: 61)])
        service.append(trackID: trackID, stepIndex: 9, notes: [note(pitch: 62)])

        let snapshot = service.captureSnapshot(trackID: trackID)

        XCTAssertEqual(snapshot.maxSteps, 16)
        XCTAssertEqual(snapshot.steps.map(\.absoluteStep), [7, 8, 9])
        XCTAssertEqual(snapshot.steps[0].notes, [])
        XCTAssertEqual(snapshot.steps[1].notes.map(\.pitch), [61])
        XCTAssertEqual(snapshot.steps[2].notes.map(\.pitch), [62])
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

    private func note(
        pitch: Int,
        velocity: Int = 100,
        length: Int = 2,
        voiceTag: VoiceTag? = nil
    ) -> GeneratedNote {
        GeneratedNote(
            pitch: pitch,
            velocity: velocity,
            length: length,
            voiceTag: voiceTag
        )
    }

    private func noteGridSteps(in content: ClipContent?) -> [ClipStep]? {
        guard case let .noteGrid(_, steps) = content else {
            return nil
        }
        return steps
    }
}
