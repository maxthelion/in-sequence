import XCTest
@testable import SequencerAI

final class MacroCoordinatorMacroParamTests: XCTestCase {

    // MARK: - Helpers

    /// Build a project with one track, one scalar macro binding, and a specific phrase cell.
    private func makeProject(
        trackID: UUID = UUID(),
        cell: PhraseCell,
        defaultValue: Double = 0
    ) -> (Project, UUID, UUID) {
        var track = StepSequenceTrack(
            id: trackID,
            name: "T",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        let bindingID = UUID()
        let descriptor = TrackMacroDescriptor(
            id: bindingID,
            displayName: "Macro",
            minValue: 0,
            maxValue: 1,
            defaultValue: defaultValue,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "x")
        )
        track.macros = [TrackMacroBinding(descriptor: descriptor)]

        var project = Project(
            version: 1,
            tracks: [track],
            selectedTrackID: trackID
        )
        // Sync macro layers into project.layers.
        project.syncMacroLayers()

        // Set the phrase cell for the macro layer.
        let layerID = "macro-\(trackID.uuidString)-\(bindingID.uuidString)"
        let phraseID = project.selectedPhraseID
        project.setPhraseCell(cell, layerID: layerID, trackIDs: [trackID], phraseID: phraseID)

        return (project, bindingID, phraseID)
    }

    // MARK: - Single cell

    func test_singleCell_yieldsValueAtEveryStep() {
        let trackID = UUID()
        let (project, bindingID, phraseID) = makeProject(
            trackID: trackID,
            cell: .single(.scalar(0.7))
        )
        let coordinator = MacroCoordinator()

        for step in [0, 1, 7, 15, 128] as [UInt64] {
            let snapshot = coordinator.snapshot(upcomingGlobalStep: step, project: project, phraseID: phraseID)
            XCTAssertEqual(
                snapshot.macroValue(trackID: trackID, bindingID: bindingID) ?? -1, 0.7,
                "step \(step) should yield 0.7"
            )
        }
    }

    // MARK: - Steps cell

    func test_stepsCell_yieldsCorrectValuePerStep() {
        let trackID = UUID()
        let values: [PhraseCellValue] = [.scalar(0.0), .scalar(0.5), .scalar(1.0), .scalar(0.5)]
        let (project, bindingID, phraseID) = makeProject(
            trackID: trackID,
            cell: .steps(values)
        )
        let coordinator = MacroCoordinator()
        let phrase = project.phrases.first(where: { $0.id == phraseID })!
        let stepCount = phrase.stepCount

        let snapshot0 = coordinator.snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID)
        let snapshot1 = coordinator.snapshot(upcomingGlobalStep: 1, project: project, phraseID: phraseID)
        let snapshot2 = coordinator.snapshot(upcomingGlobalStep: 2, project: project, phraseID: phraseID)
        let snapshot3 = coordinator.snapshot(upcomingGlobalStep: 3, project: project, phraseID: phraseID)

        XCTAssertEqual(snapshot0.macroValue(trackID: trackID, bindingID: bindingID) ?? -1, 0.0, accuracy: 0.001)
        XCTAssertEqual(snapshot1.macroValue(trackID: trackID, bindingID: bindingID) ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(snapshot2.macroValue(trackID: trackID, bindingID: bindingID) ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(snapshot3.macroValue(trackID: trackID, bindingID: bindingID) ?? -1, 0.5, accuracy: 0.001)
        _ = stepCount
    }

    // MARK: - Curve cell

    func test_curveCell_interpolates() {
        let trackID = UUID()
        // A straight ramp from 0 to 1 across the phrase.
        let (project, bindingID, phraseID) = makeProject(
            trackID: trackID,
            cell: .curve([0.0, 1.0])
        )
        let coordinator = MacroCoordinator()
        let phrase = project.phrases.first(where: { $0.id == phraseID })!
        let lastStep = UInt64(phrase.stepCount - 1)

        let snapshotStart = coordinator.snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID)
        let snapshotEnd = coordinator.snapshot(upcomingGlobalStep: lastStep, project: project, phraseID: phraseID)

        let startValue = snapshotStart.macroValue(trackID: trackID, bindingID: bindingID) ?? -1
        let endValue = snapshotEnd.macroValue(trackID: trackID, bindingID: bindingID) ?? -1
        XCTAssertLessThan(startValue, endValue, "curve should ramp from low to high")
        XCTAssertLessThan(startValue, 0.5)
        XCTAssertGreaterThan(endValue, 0.5)
    }

    // MARK: - Binding removal

    func test_removedBinding_notInSnapshot() {
        let trackID = UUID()
        var (project, bindingID, phraseID) = makeProject(
            trackID: trackID,
            cell: .single(.scalar(0.9))
        )
        // Confirm it's present.
        let before = MacroCoordinator().snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID)
        XCTAssertNotNil(before.macroValue(trackID: trackID, bindingID: bindingID))

        // Remove the binding.
        project.removeMacro(id: bindingID, from: trackID)
        project.syncMacroLayers()

        let after = MacroCoordinator().snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID)
        XCTAssertNil(after.macroValue(trackID: trackID, bindingID: bindingID))
    }

    // MARK: - InheritDefault

    func test_inheritDefault_yieldsDescriptorDefault() {
        let trackID = UUID()
        let (project, bindingID, phraseID) = makeProject(
            trackID: trackID,
            cell: .inheritDefault,
            defaultValue: 0.42
        )
        let snapshot = MacroCoordinator().snapshot(upcomingGlobalStep: 0, project: project, phraseID: phraseID)
        XCTAssertEqual(snapshot.macroValue(trackID: trackID, bindingID: bindingID) ?? -1, 0.42, accuracy: 0.001)
    }
}
