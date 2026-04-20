import XCTest
@testable import SequencerAI

final class MacroCoordinatorTests: XCTestCase {
    private func project(withMuteCell cell: PhraseCell, for trackID: UUID) -> (Project, UUID) {
        let track = StepSequenceTrack(
            id: trackID,
            name: "A",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let muteLayer = try! XCTUnwrap(layers.first(where: { $0.target == .mute }))
        var phrase = PhraseModel.default(tracks: [track], layers: layers)
        phrase.setCell(cell, for: muteLayer.id, trackID: trackID)
        let project = Project(
            version: 1,
            tracks: [track],
            layers: layers,
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, phrase.id)
    }

    func test_inheritDefault_returnsEmptyMuteSnapshot() {
        let trackID = UUID()
        let (project, phraseID) = project(withMuteCell: .inheritDefault, for: trackID)

        let snapshot = MacroCoordinator().snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID)

        XCTAssertFalse(snapshot.isMuted(trackID))
    }

    func test_singleTrue_mutesAtEveryStep() {
        let trackID = UUID()
        let (project, phraseID) = project(withMuteCell: .single(.bool(true)), for: trackID)
        let coordinator = MacroCoordinator()

        for step in [0, 1, 7, 15, 128] as [UInt64] {
            XCTAssertTrue(
                coordinator.snapshot(upcomingGlobalStep: step, project: project, phraseID: phraseID).isMuted(trackID),
                "step \(step) should be muted"
            )
        }
    }

    func test_barsCell_switchesMuteByBar() {
        let trackID = UUID()
        let bars: [PhraseCellValue] = [
            .bool(false), .bool(true), .bool(false), .bool(true),
            .bool(false), .bool(true), .bool(false), .bool(true),
        ]
        let (project, phraseID) = project(withMuteCell: .bars(bars), for: trackID)
        let coordinator = MacroCoordinator()

        XCTAssertFalse(coordinator.snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertTrue(coordinator.snapshot(upcomingGlobalStep: 16, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertFalse(coordinator.snapshot(upcomingGlobalStep: 32, project: project, phraseID: phraseID).isMuted(trackID))
    }

    func test_stepsCell_switchesMutePerStep() {
        let trackID = UUID()
        let steps: [PhraseCellValue] = (0..<128).map { .bool($0 % 2 == 1) }
        let (project, phraseID) = project(withMuteCell: .steps(steps), for: trackID)
        let coordinator = MacroCoordinator()

        XCTAssertFalse(coordinator.snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertTrue(coordinator.snapshot(upcomingGlobalStep: 1, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertFalse(coordinator.snapshot(upcomingGlobalStep: 2, project: project, phraseID: phraseID).isMuted(trackID))
    }

    func test_globalStepWrapsByPhraseLength() {
        let trackID = UUID()
        let steps: [PhraseCellValue] = (0..<128).map { .bool($0 == 5) }
        let (project, phraseID) = project(withMuteCell: .steps(steps), for: trackID)
        let coordinator = MacroCoordinator()

        XCTAssertTrue(coordinator.snapshot(upcomingGlobalStep: 5, project: project, phraseID: phraseID).isMuted(trackID))
        XCTAssertTrue(coordinator.snapshot(upcomingGlobalStep: 133, project: project, phraseID: phraseID).isMuted(trackID))
    }

    func test_missingPhrase_returnsEmpty() {
        let track = StepSequenceTrack(name: "A", pitches: [60], stepPattern: [true], velocity: 100, gateLength: 4)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = Project(
            version: 1,
            tracks: [track],
            layers: layers,
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: UUID()
        )

        let snapshot = MacroCoordinator().snapshot(upcomingGlobalStep: 0, project: project, phraseID: UUID())

        XCTAssertTrue(snapshot.mute.isEmpty)
    }
}
