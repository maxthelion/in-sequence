import XCTest
@testable import SequencerAI

// Phase 1b guardrail tests — store read helpers mirror their Project equivalents.
//
// Each test:
//  1. Imports a non-trivial `Project` fixture into a `LiveSequencerStore`.
//  2. Calls the store helper.
//  3. Calls the equivalent `Project` helper on the exported project.
//  4. Asserts the two outputs are equal.
//
// This proves the port is faithful. Any semantic divergence is documented inline.

@MainActor
final class StoreAccessorHelpersTests: XCTestCase {

    // MARK: - Fixture helpers

    private func makeFixture() -> (store: LiveSequencerStore, project: Project, trackID: UUID, clipID: UUID, phraseID: UUID) {
        let (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60)
        let store = LiveSequencerStore(project: project)
        let phraseID = project.selectedPhraseID
        return (store, project, trackID, clipID, phraseID)
    }

    /// A richer fixture with two tracks, a group, and a route.
    private func makeRichFixture() -> (store: LiveSequencerStore, project: Project) {
        let trackID1 = UUID()
        let trackID2 = UUID()
        let clipID1 = UUID()
        let clipID2 = UUID()
        let groupID = UUID()

        let track1 = StepSequenceTrack(
            id: trackID1,
            name: "Alpha",
            pitches: [48],
            stepPattern: [true, false],
            stepAccents: [false, false],
            destination: .none,
            groupID: nil,
            velocity: 80,
            gateLength: 4
        )
        let track2 = StepSequenceTrack(
            id: trackID2,
            name: "Beta",
            pitches: [60],
            stepPattern: [false, true],
            stepAccents: [false, false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 96,
            gateLength: 4
        )

        let clip1 = ClipPoolEntry(
            id: clipID1,
            name: "Clip A",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 2,
                steps: [
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 1)]), fill: nil),
                    .empty
                ]
            )
        )
        let clip2 = ClipPoolEntry(
            id: clipID2,
            name: "Clip B",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 80, lengthSteps: 1)]), fill: nil)]
            )
        )

        let layers = PhraseLayerDefinition.defaultSet(for: [track1, track2])
        let phrase = PhraseModel.default(
            tracks: [track1, track2],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip1, clip2]
        )

        let bank1 = TrackPatternBank(
            trackID: trackID1,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipID1))]
        )
        let bank2 = TrackPatternBank(
            trackID: trackID2,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipID2))]
        )

        let group = TrackGroup(
            id: groupID,
            name: "Group A",
            color: "#AAA",
            memberIDs: [trackID2],
            sharedDestination: .none
        )

        let route = Route(
            source: .track(trackID1),
            destination: .voicing(trackID2)
        )

        let project = Project(
            version: 1,
            tracks: [track1, track2],
            trackGroups: [group],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip1, clip2],
            layers: layers,
            routes: [route],
            patternBanks: [bank1, bank2],
            selectedTrackID: trackID1,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let store = LiveSequencerStore(project: project)
        return (store, project)
    }

    // MARK: - selectedTrack

    func test_selectedTrack_matchesProject() {
        let (store, project, _, _, _) = makeFixture()
        XCTAssertEqual(store.selectedTrack, project.selectedTrack)
    }

    func test_selectedTrack_fallsBackToDefault_whenTracksEmpty() {
        // Build a minimal store with no tracks by importing an empty-ish project.
        // We can't easily make Project.empty have zero tracks (it always has at least one),
        // but we can verify the fallback path is the same sentinel value on both sides.
        // Project always has at least one track so we test via store directly.
        let emptyProject = Project.empty
        let store = LiveSequencerStore(project: emptyProject)
        // Store must return the same value as project.selectedTrack.
        XCTAssertEqual(store.selectedTrack, emptyProject.selectedTrack)
    }

    // MARK: - selectedPhrase

    func test_selectedPhrase_matchesProject() {
        let (store, project, _, _, _) = makeFixture()
        XCTAssertEqual(store.selectedPhrase, project.selectedPhrase)
    }

    // MARK: - patternLayer

    func test_patternLayer_matchesProject() {
        let (store, project, _, _, _) = makeFixture()
        XCTAssertEqual(store.patternLayer, project.patternLayer)
    }

    // MARK: - patternBank(for:)

    func test_patternBank_matchesProject() {
        let (store, project, trackID, _, _) = makeFixture()
        XCTAssertEqual(store.patternBank(for: trackID), project.patternBank(for: trackID))
    }

    func test_patternBank_synthesisedDefault_matchesProject() {
        let (store, project, _, _, _) = makeFixture()
        let unknownTrackID = UUID()
        // Both should synthesise identical defaults for an unknown track ID.
        XCTAssertEqual(
            store.patternBank(for: unknownTrackID),
            project.patternBank(for: unknownTrackID)
        )
    }

    // MARK: - selectedPatternIndex(for:)

    func test_selectedPatternIndex_matchesProject() {
        let (store, project, trackID, _, _) = makeFixture()
        XCTAssertEqual(
            store.selectedPatternIndex(for: trackID),
            project.selectedPatternIndex(for: trackID)
        )
    }

    // MARK: - selectedPattern(for:)

    func test_selectedPattern_matchesProject() {
        let (store, project, trackID, _, _) = makeFixture()
        XCTAssertEqual(
            store.selectedPattern(for: trackID),
            project.selectedPattern(for: trackID)
        )
    }

    // MARK: - layer(id:)

    func test_layer_matchesProject() {
        let (store, project, _, _, _) = makeFixture()
        guard let firstLayer = project.layers.first else {
            XCTFail("fixture must have at least one layer")
            return
        }
        XCTAssertEqual(
            store.layer(id: firstLayer.id),
            project.layer(id: firstLayer.id)
        )
    }

    func test_layer_returnsNil_forUnknownID() {
        let (store, project, _, _, _) = makeFixture()
        XCTAssertNil(store.layer(id: "unknown-layer-id"))
        XCTAssertNil(project.layer(id: "unknown-layer-id"))
    }

    // MARK: - clipEntry(id:)

    func test_clipEntry_matchesProject() {
        let (store, project, _, clipID, _) = makeFixture()
        XCTAssertEqual(store.clipEntry(id: clipID), project.clipEntry(id: clipID))
    }

    func test_clipEntry_returnsNil_forNilID() {
        let (store, project, _, _, _) = makeFixture()
        XCTAssertNil(store.clipEntry(id: nil))
        XCTAssertNil(project.clipEntry(id: nil))
    }

    // MARK: - generatorEntry(id:)

    func test_generatorEntry_matchesProject() {
        let (store, project, _, _, _) = makeFixture()
        let generatorID = project.generatorPool.first?.id
        XCTAssertEqual(store.generatorEntry(id: generatorID), project.generatorEntry(id: generatorID))
    }

    func test_generatorEntry_returnsNil_forNilID() {
        let (store, project, _, _, _) = makeFixture()
        XCTAssertNil(store.generatorEntry(id: nil))
        XCTAssertNil(project.generatorEntry(id: nil))
    }

    // MARK: - compatibleGenerators(for:)

    func test_compatibleGenerators_matchesProject() {
        let (store, project, trackID, _, _) = makeFixture()
        let track = project.tracks.first(where: { $0.id == trackID })!
        XCTAssertEqual(
            store.compatibleGenerators(for: track),
            project.compatibleGenerators(for: track)
        )
    }

    // MARK: - generatedSourceInputClips()

    func test_generatedSourceInputClips_matchesProject() {
        let (store, project, _, _, _) = makeFixture()
        XCTAssertEqual(store.generatedSourceInputClips(), project.generatedSourceInputClips())
    }

    // MARK: - harmonicSidechainClips()

    func test_harmonicSidechainClips_matchesProject() {
        let (store, project, _, _, _) = makeFixture()
        XCTAssertEqual(store.harmonicSidechainClips(), project.harmonicSidechainClips())
    }

    // MARK: - group(for:) and tracksInGroup(_:)

    func test_group_matchesProject() {
        let (store, project) = makeRichFixture()
        let trackID = project.tracks[1].id
        XCTAssertEqual(store.group(for: trackID), project.group(for: trackID))
    }

    func test_group_returnsNil_forUngroupedTrack() {
        let (store, project) = makeRichFixture()
        let trackID = project.tracks[0].id
        XCTAssertNil(store.group(for: trackID))
        XCTAssertNil(project.group(for: trackID))
    }

    func test_tracksInGroup_matchesProject() {
        let (store, project) = makeRichFixture()
        let groupID = project.trackGroups.first!.id
        XCTAssertEqual(store.tracksInGroup(groupID), project.tracksInGroup(groupID))
    }

    // MARK: - destinationWriteTarget(for:)

    func test_destinationWriteTarget_matchesProject() {
        let (store, project) = makeRichFixture()
        for track in project.tracks {
            XCTAssertEqual(
                store.destinationWriteTarget(for: track.id),
                project.destinationWriteTarget(for: track.id),
                "Mismatch for track \(track.name)"
            )
        }
    }

    // MARK: - resolvedDestination(for:)

    func test_resolvedDestination_matchesProject() {
        let (store, project) = makeRichFixture()
        for track in project.tracks {
            XCTAssertEqual(
                store.resolvedDestination(for: track.id),
                project.resolvedDestination(for: track.id),
                "Mismatch for track \(track.name)"
            )
        }
    }

    // MARK: - voiceSnapshotDestination(for:)

    func test_voiceSnapshotDestination_matchesProject() {
        let (store, project) = makeRichFixture()
        for track in project.tracks {
            XCTAssertEqual(
                store.voiceSnapshotDestination(for: track.id),
                project.voiceSnapshotDestination(for: track.id),
                "Mismatch for track \(track.name)"
            )
        }
    }

    // MARK: - routesSourced(from:)

    func test_routesSourced_matchesProject() {
        let (store, project) = makeRichFixture()
        let sourceTrackID = project.tracks[0].id
        XCTAssertEqual(
            store.routesSourced(from: sourceTrackID),
            project.routesSourced(from: sourceTrackID)
        )
    }

    func test_routesSourced_returnsEmpty_forNonSourceTrack() {
        let (store, project) = makeRichFixture()
        let nonSourceTrackID = project.tracks[1].id
        XCTAssertTrue(store.routesSourced(from: nonSourceTrackID).isEmpty)
        XCTAssertTrue(project.routesSourced(from: nonSourceTrackID).isEmpty)
    }

    // MARK: - exportToProjectCallCount spy

    func test_exportToProjectCallCount_incrementsOnExport() {
        let (store, _, _, _, _) = makeFixture()
        let before = store.exportToProjectCallCount
        _ = store.exportToProject()
        XCTAssertEqual(store.exportToProjectCallCount, before + 1)
    }

    func test_accessorHelpers_doNotCallExportToProject() {
        let (store, _, trackID, clipID, _) = makeFixture()
        assertNoExportDuring(store) {
            _ = store.selectedTrack
            _ = store.selectedPhrase
            _ = store.patternLayer
            _ = store.patternBank(for: trackID)
            _ = store.selectedPatternIndex(for: trackID)
            _ = store.selectedPattern(for: trackID)
            _ = store.clipEntry(id: clipID)
            _ = store.generatorEntry(id: nil)
            _ = store.generatedSourceInputClips()
            _ = store.harmonicSidechainClips()
        }
    }
}
