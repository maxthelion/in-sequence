import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class PhrasePerformOverlaySessionTests: XCTestCase {
    func test_requestPhrasePerformStoresLayerEditModeAndTrackScope() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        let scopedTrackIDs = Set(fixture.trackIDs.prefix(2))
        fixture.session.requestPhrasePerform(
            tab: .layers,
            layerEditMode: .byValue,
            trackIDs: scopedTrackIDs
        )

        XCTAssertEqual(fixture.session.performTrackScope, scopedTrackIDs)
        XCTAssertEqual(fixture.session.pendingPhrasePerform?.tab, .layers)
        XCTAssertEqual(fixture.session.pendingPhrasePerform?.layerEditMode, .byValue)
        XCTAssertEqual(fixture.session.pendingPhrasePerform?.trackIDs, scopedTrackIDs)
    }

    func test_phraseTabsPromoteLayerAndValuesToTopLevelDestinations() {
        XCTAssertEqual(PhraseWorkspaceTab.allCases, [.layers, .values, .scenes])
        XCTAssertEqual(PhraseWorkspaceTab.layers.label, "Layer")
        XCTAssertEqual(PhraseWorkspaceTab.values.label, "Values")
        XCTAssertEqual(PhraseLayerEditMode.allCases, [.byTrack, .byValue])
    }

    func test_phraseSceneViewModesOfferMacrosAndSlots() {
        XCTAssertEqual(PhraseSceneViewMode.allCases, [.macros, .slots])
        XCTAssertEqual(PhraseSceneViewMode.macros.label, "Macros")
        XCTAssertEqual(PhraseSceneViewMode.slots.label, "Slots")
    }

    func test_stagePhrasePerformCell_readsFromOverlayWithoutChangingCanonicalPhrase() throws {
        let fixture = makeSession()
        defer { fixture.unregister() }

        XCTAssertTrue(fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        ))

        XCTAssertEqual(
            fixture.session.store.phrases[0].cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .inheritDefault
        )
        XCTAssertEqual(
            fixture.session.phraseWithPerformOverlay(fixture.session.store.phrases[0])
                .cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .single(.bool(true))
        )
        XCTAssertTrue(fixture.session.phrasePerformOverlay.isDirty)
    }

    func test_setPhraseCellInSetupModeMutatesCanonicalPhrase() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.workspaceMode = .setup
        fixture.session.setPhraseCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            phraseID: fixture.phrases[0].id
        )

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(
            fixture.session.store.phrases[0].cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .single(.bool(true))
        )
    }

    func test_setPhraseCellInPerformModeStagesOverlayWithoutMutatingCanonicalPhrase() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.workspaceMode = .perform
        fixture.session.setPhraseCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            phraseID: fixture.phrases[0].id
        )

        XCTAssertTrue(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(fixture.session.phrasePerformOverlay.basisPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(
            fixture.session.store.phrases[0].cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .inheritDefault
        )
        XCTAssertEqual(
            fixture.session.phraseWithPerformOverlay(fixture.session.store.phrases[0])
                .cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .single(.bool(true))
        )
    }

    func test_enteringPerformModeBeginsCleanLivePhraseCopy() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.workspaceMode = .perform

        XCTAssertTrue(fixture.session.phrasePerformOverlay.hasLiveCopy)
        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(fixture.session.phrasePerformOverlay.basisPhraseID, fixture.phrases[0].id)
    }

    func test_cleanPerformCopyFollowsSelectedPhraseUntilDirty() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.workspaceMode = .perform
        fixture.session.setSelectedPhraseID(fixture.phrases[1].id)

        XCTAssertTrue(fixture.session.phrasePerformOverlay.hasLiveCopy)
        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(fixture.session.phrasePerformOverlay.basisPhraseID, fixture.phrases[1].id)
    }

    func test_automationStyleCellReplacementInPerformModeStagesOverlay() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.workspaceMode = .perform
        fixture.session.setPhraseCell(
            .bars([.bool(true), .bool(false), .bool(true), .bool(false)]),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            phraseID: fixture.phrases[0].id
        )

        XCTAssertTrue(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(
            fixture.session.store.phrases[0].cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .inheritDefault
        )
        XCTAssertEqual(
            fixture.session.phraseWithPerformOverlay(fixture.session.store.phrases[0])
                .cell(for: fixture.muteLayerID, trackID: fixture.trackID),
                .bars([.bool(true), .bool(false), .bool(true), .bool(false)])
        )
    }

    func test_scopedByValueInPerformModeStagesEveryRecipientTrack() throws {
        let fixture = makeSession()
        defer { fixture.unregister() }

        let recipientTrackIDs = Array(fixture.trackIDs.prefix(2))
        try XCTSkipIf(recipientTrackIDs.count < 2, "Fixture needs at least two tracks for scoped By Value coverage")

        fixture.session.workspaceMode = .perform
        fixture.session.setPhraseCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: recipientTrackIDs,
            phraseID: fixture.phrases[0].id
        )

        XCTAssertEqual(fixture.session.phrasePerformOverlay.stagedCellCount, recipientTrackIDs.count)
        for trackID in recipientTrackIDs {
            XCTAssertEqual(
                fixture.session.store.phrases[0].cell(for: fixture.muteLayerID, trackID: trackID),
                .inheritDefault
            )
            XCTAssertEqual(
                fixture.session.phraseWithPerformOverlay(fixture.session.store.phrases[0])
                    .cell(for: fixture.muteLayerID, trackID: trackID),
                .single(.bool(true))
            )
        }
    }

    func test_performOverlayPublishesEngineVisiblePhrasePlaybackState() throws {
        let fixture = makeSession()
        defer { fixture.unregister() }

        let phraseID = fixture.phrases[0].id
        fixture.session.workspaceMode = .perform
        XCTAssertTrue(fixture.session.setPhraseRepeatCount(3, phraseID: phraseID))
        XCTAssertTrue(fixture.session.setPhraseLoopEnabled(true, phraseID: phraseID))

        fixture.session.setPhraseCell(
            .single(.index(1)),
            layerID: "pattern",
            trackIDs: [fixture.trackID],
            phraseID: phraseID
        )
        fixture.session.setPhraseCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            phraseID: phraseID
        )
        fixture.session.setPhraseCell(
            .single(.bool(true)),
            layerID: "fill-flag",
            trackIDs: [fixture.trackID],
            phraseID: phraseID
        )

        let sceneState = PhraseSceneState(
            sceneAID: fixture.sceneAID,
            sceneBID: fixture.sceneBID,
            crossfader: 0.65
        )
        fixture.session.setPhraseSceneState(sceneState, phraseID: phraseID)

        let snapshot = fixture.engine.currentPlaybackSnapshotForTesting
        let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffer(for: phraseID))
        let trackState = try XCTUnwrap(phraseBuffer.trackState(for: fixture.trackID))
        let resolvedStep = try XCTUnwrap(snapshot.resolvedStep(
            phraseID: phraseID,
            trackID: fixture.trackID,
            stepInPhrase: 0
        ))

        XCTAssertEqual(phraseBuffer.repeatCount, 3)
        XCTAssertTrue(phraseBuffer.loopEnabled)
        XCTAssertEqual(phraseBuffer.sceneState, sceneState.normalized())
        XCTAssertEqual(trackState.patternSlotIndex[0], 1)
        XCTAssertTrue(trackState.mute[0])
        XCTAssertTrue(trackState.fillEnabled[0])
        XCTAssertEqual(resolvedStep.slotIndex, 1)
        XCTAssertTrue(resolvedStep.mute)
        XCTAssertTrue(resolvedStep.fillEnabled)
    }

    func test_performModeDirectLayerChangesPublishImmediatelyWithoutTransport() throws {
        let fixture = makeSession()
        defer { fixture.unregister() }

        let phraseID = fixture.phrases[0].id
        fixture.session.workspaceMode = .perform

        fixture.session.setPhraseCell(
            .single(.index(1)),
            layerID: "pattern",
            trackIDs: [fixture.trackID],
            phraseID: phraseID
        )
        XCTAssertEqual(
            fixture.engine.currentPlaybackSnapshotForTesting.resolvedStep(
                phraseID: phraseID,
                trackID: fixture.trackID,
                stepInPhrase: 0
            )?.slotIndex,
            1
        )

        fixture.session.setPhraseCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            phraseID: phraseID
        )
        XCTAssertTrue(
            try XCTUnwrap(fixture.engine.currentPlaybackSnapshotForTesting.resolvedStep(
                phraseID: phraseID,
                trackID: fixture.trackID,
                stepInPhrase: 0
            )).mute
        )

        fixture.session.setPhraseCell(
            .single(.bool(true)),
            layerID: "fill-flag",
            trackIDs: [fixture.trackID],
            phraseID: phraseID
        )
        XCTAssertTrue(
            try XCTUnwrap(fixture.engine.currentPlaybackSnapshotForTesting.resolvedStep(
                phraseID: phraseID,
                trackID: fixture.trackID,
                stepInPhrase: 0
            )).fillEnabled
        )
        XCTAssertTrue(fixture.engine.quantisedPendingChanges.isEmpty)
    }

    func test_setPhraseSceneStateInSetupModeMutatesCanonicalPhrase() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        let state = PhraseSceneState(
            sceneAID: fixture.sceneAID,
            sceneBID: fixture.sceneBID,
            crossfader: 0.7
        )

        fixture.session.workspaceMode = .setup
        fixture.session.setPhraseSceneState(state, phraseID: fixture.phrases[0].id)

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(fixture.session.store.phrases[0].sceneState, state)
        XCTAssertEqual(
            fixture.session.resolvedPhraseSceneState(for: fixture.session.store.phrases[0]),
            state
        )
    }

    func test_setPhraseSceneStateInPerformModeStagesOverlayWithoutMutatingCanonicalPhrase() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        let state = PhraseSceneState(
            sceneAID: fixture.sceneAID,
            sceneBID: fixture.sceneBID,
            crossfader: 0.7
        )

        fixture.session.workspaceMode = .perform
        fixture.session.setPhraseSceneState(state, phraseID: fixture.phrases[0].id)

        XCTAssertTrue(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(fixture.session.phrasePerformOverlay.basisPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.session.phrasePerformOverlay.stagedCellCount, 0)
        XCTAssertEqual(fixture.session.phrasePerformOverlay.stagedChangeCount, 1)
        XCTAssertNil(fixture.session.store.phrases[0].sceneState)
        XCTAssertEqual(
            fixture.session.performOverlaySceneState(phraseID: fixture.phrases[0].id),
            state
        )
        XCTAssertEqual(
            fixture.session.phraseWithPerformOverlay(fixture.session.store.phrases[0]).sceneState,
            state
        )
    }

    // Slots-matrix tap semantics: a scene assignment while perform is on is
    // staged into the overlay only, and lands on a phrase only when captured.
    func test_performModeSceneSlotAssignmentStaysStagedUntilCaptured() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.workspaceMode = .perform
        let state = PhraseSceneState(
            sceneAID: fixture.sceneBID,
            sceneBID: fixture.sceneAID,
            crossfader: 0.25
        )
        fixture.session.setPhraseSceneState(state, phraseID: fixture.phrases[0].id)

        XCTAssertTrue(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertNil(fixture.session.store.phrases[0].sceneState)
        XCTAssertNil(fixture.session.store.phrases[1].sceneState)

        XCTAssertTrue(fixture.session.capturePhrasePerformOverlay(to: fixture.phrases[1].id))

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertNil(fixture.session.store.phrases[0].sceneState)
        XCTAssertEqual(fixture.session.store.phrases[1].sceneState, state)
    }

    func test_savePhrasePerformOverlayBack_appliesStagedSceneStateAndClearsOverlay() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        let state = PhraseSceneState(
            sceneAID: fixture.sceneAID,
            sceneBID: fixture.sceneBID,
            crossfader: 0.7
        )
        fixture.session.stagePhrasePerformSceneState(state, basisPhraseID: fixture.phrases[0].id)

        XCTAssertTrue(fixture.session.savePhrasePerformOverlayBack())

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(fixture.session.store.phrases[0].sceneState, state)
    }

    func test_capturePhrasePerformOverlayToExistingPhraseCopiesSceneState() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        let state = PhraseSceneState(
            sceneAID: fixture.sceneAID,
            sceneBID: fixture.sceneBID,
            crossfader: 0.7
        )
        fixture.session.stagePhrasePerformSceneState(state, basisPhraseID: fixture.phrases[0].id)

        XCTAssertTrue(fixture.session.capturePhrasePerformOverlay(to: fixture.phrases[1].id))

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(fixture.session.store.phrases[1].id, fixture.phrases[1].id)
        XCTAssertEqual(fixture.session.store.phrases[1].name, fixture.phrases[1].name)
        XCTAssertEqual(fixture.session.store.phrases[1].sceneState, state)
    }

    func test_revertPhrasePerformOverlay_discardsStagedCellsOnly() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.setPhraseBarCount(2, phraseID: fixture.phrases[0].id)
        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )

        fixture.session.revertPhrasePerformOverlay()

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(
            fixture.session.store.phrases[0].cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .inheritDefault
        )
        XCTAssertEqual(fixture.session.store.phrases[0].lengthBars, 2)
    }

    func test_savePhrasePerformOverlayBack_appliesStagedCellsAndClearsOverlay() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )

        XCTAssertTrue(fixture.session.savePhrasePerformOverlayBack())

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(
            fixture.session.store.phrases[0].cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .single(.bool(true))
        )
    }

    func test_capturePhrasePerformOverlayToExistingPhraseCopiesHeardBasisState() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.setPhraseBarCount(4, phraseID: fixture.phrases[0].id)
        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )

        XCTAssertTrue(fixture.session.capturePhrasePerformOverlay(to: fixture.phrases[1].id))

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(fixture.session.store.phrases[1].id, fixture.phrases[1].id)
        XCTAssertEqual(fixture.session.store.phrases[1].name, fixture.phrases[1].name)
        XCTAssertEqual(fixture.session.store.phrases[1].lengthBars, 4)
        XCTAssertEqual(
            fixture.session.store.phrases[1].cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .single(.bool(true))
        )
    }

    func test_capturePhrasePerformOverlayToNewPhraseCreatesReusableCopy() throws {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.setPhraseBarCount(3, phraseID: fixture.phrases[0].id)
        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )

        let newPhraseID = try XCTUnwrap(fixture.session.capturePhrasePerformOverlayToNewPhrase())

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        let newPhrase = try XCTUnwrap(fixture.session.store.phrases.first(where: { $0.id == newPhraseID }))
        XCTAssertEqual(newPhrase.name, "Phrase C")
        XCTAssertEqual(newPhrase.lengthBars, 3)
        XCTAssertEqual(
            newPhrase.cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .single(.bool(true))
        )
        XCTAssertEqual(fixture.session.store.selectedPhraseID, newPhraseID)
    }

    func test_captureCleanPerformCopyToNewPhraseDuplicatesBasisPhrase() throws {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.workspaceMode = .perform

        let newPhraseID = try XCTUnwrap(fixture.session.capturePhrasePerformOverlayToNewPhrase())
        let capturedPhrase = try XCTUnwrap(fixture.session.store.phrases.first { $0.id == newPhraseID })

        XCTAssertFalse(fixture.session.phrasePerformOverlay.hasLiveCopy)
        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertEqual(capturedPhrase.name, "Phrase C")
        XCTAssertEqual(
            capturedPhrase.cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            fixture.phrases[0].cell(for: fixture.muteLayerID, trackID: fixture.trackID)
        )
        XCTAssertEqual(capturedPhrase.sceneState, fixture.phrases[0].sceneState)
    }

    func test_performOverlayCellAndStagedCountReflectStagedEditsForDirtyRingAndCounter() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        // No edits staged: counter reads zero and no cell is dirty.
        XCTAssertEqual(fixture.session.phrasePerformOverlay.stagedCellCount, 0)
        XCTAssertNil(fixture.session.performOverlayCell(
            phraseID: fixture.phrases[0].id,
            layerID: fixture.muteLayerID,
            trackID: fixture.trackID
        ))

        // Stage one cell on the mute layer.
        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )

        XCTAssertEqual(fixture.session.phrasePerformOverlay.stagedCellCount, 1)
        // The dirty-ring lookup the matrix card uses returns the staged cell
        // for the basis phrase/layer/track...
        XCTAssertEqual(
            fixture.session.performOverlayCell(
                phraseID: fixture.phrases[0].id,
                layerID: fixture.muteLayerID,
                trackID: fixture.trackID
            ),
            .single(.bool(true))
        )
        // ...and nil for a layer that was not edited.
        XCTAssertNil(fixture.session.performOverlayCell(
            phraseID: fixture.phrases[0].id,
            layerID: "volume",
            trackID: fixture.trackID
        ))
        // ...and nil for a different (non-basis) phrase.
        XCTAssertNil(fixture.session.performOverlayCell(
            phraseID: fixture.phrases[1].id,
            layerID: fixture.muteLayerID,
            trackID: fixture.trackID
        ))

        // Stage a second distinct cell: the edit counter advances to 2.
        fixture.session.stagePhrasePerformCell(
            .single(.scalar(0.5)),
            layerID: "volume",
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )
        XCTAssertEqual(fixture.session.phrasePerformOverlay.stagedCellCount, 2)
        XCTAssertNotNil(fixture.session.performOverlayCell(
            phraseID: fixture.phrases[0].id,
            layerID: "volume",
            trackID: fixture.trackID
        ))

        // Revert clears both the counter and the per-cell dirty indicator.
        fixture.session.revertPhrasePerformOverlay()
        XCTAssertEqual(fixture.session.phrasePerformOverlay.stagedCellCount, 0)
        XCTAssertNil(fixture.session.performOverlayCell(
            phraseID: fixture.phrases[0].id,
            layerID: fixture.muteLayerID,
            trackID: fixture.trackID
        ))
    }

    func test_dirtyOverlayBlocksBasisPhraseSelectionAndNavigationUntilResolved() {
        let fixture = makeSession()
        defer {
            fixture.engine.stop()
            fixture.unregister()
        }

        fixture.engine.start()
        fixture.engine.clock.stop()
        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )

        fixture.session.setSelectedPhraseID(fixture.phrases[1].id)
        XCTAssertEqual(fixture.session.store.selectedPhraseID, fixture.phrases[0].id)
        XCTAssertFalse(fixture.session.queuePhrase(fixture.phrases[1].id))
        XCTAssertFalse(fixture.session.switchPhraseNow(fixture.phrases[1].id))
        XCTAssertNotEqual(fixture.engine.basisPhraseID, fixture.phrases[1].id)

        fixture.session.revertPhrasePerformOverlay()

        XCTAssertTrue(fixture.session.switchPhraseNow(fixture.phrases[1].id))
        XCTAssertEqual(fixture.engine.basisPhraseID, fixture.phrases[1].id)
    }

    func test_structuralPhraseControlsRemainCanonicalAfterRevert() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )
        fixture.session.setPhraseBarCount(3, phraseID: fixture.phrases[0].id)
        fixture.session.setPhraseRepeatCount(4, phraseID: fixture.phrases[0].id)
        fixture.session.setPhraseLoopEnabled(true, phraseID: fixture.phrases[0].id)

        fixture.session.revertPhrasePerformOverlay()

        let phrase = fixture.session.store.phrases[0]
        XCTAssertEqual(phrase.lengthBars, 3)
        XCTAssertEqual(phrase.repeatCount, 4)
        XCTAssertTrue(phrase.loopEnabled)
        XCTAssertEqual(phrase.cell(for: fixture.muteLayerID, trackID: fixture.trackID), .inheritDefault)
    }

    func test_deletingBasisPhraseClearsPendingOverlayAndDisablesSaveBack() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )

        fixture.session.removePhrase(id: fixture.phrases[0].id)

        XCTAssertFalse(fixture.session.phrasePerformOverlay.isDirty)
        XCTAssertFalse(fixture.session.savePhrasePerformOverlayBack())
        XCTAssertFalse(fixture.session.store.phrases.contains(where: { $0.id == fixture.phrases[0].id }))
    }

    func test_overlayIsRuntimeOnlyAndDoesNotPersistAcrossDocumentReopen() {
        let fixture = makeSession()
        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )
        fixture.session.flushToDocumentSync()

        let reopenedBox = PhrasePerformOverlayDocumentBox(document: fixture.documentBox.document)
        let reopenedSession = SequencerDocumentSession(
            document: Binding(
                get: { reopenedBox.document },
                set: { reopenedBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )
        defer {
            fixture.unregister()
            SequencerDocumentSessionRegistry.unregister(reopenedSession)
        }

        XCTAssertFalse(reopenedSession.phrasePerformOverlay.isDirty)
        XCTAssertEqual(
            reopenedSession.store.phrases[0].cell(for: fixture.muteLayerID, trackID: fixture.trackID),
            .inheritDefault
        )
    }

    func test_dirtyOverlayRemainsPendingUntilExplicitSaveBackOrRevert() {
        let fixture = makeSession()
        defer { fixture.unregister() }

        fixture.session.stagePhrasePerformCell(
            .single(.bool(true)),
            layerID: fixture.muteLayerID,
            trackIDs: [fixture.trackID],
            basisPhraseID: fixture.phrases[0].id
        )
        fixture.session.setSelectedTrackID(fixture.trackID)

        XCTAssertTrue(fixture.session.phrasePerformOverlay.isDirty)
    }

    private func makeSession() -> PhrasePerformOverlayFixture {
        var project = makeLiveStoreProject().0
        let trackID = project.selectedTrackID
        let muteLayerID = project.layers.first(where: { $0.target == .mute })!.id
        let sceneIDs = project.masterBus.scenes.map(\.id)

        var firstPhrase = project.phrases[0]
        firstPhrase.id = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        firstPhrase.name = "Basis A"
        var secondPhrase = firstPhrase
        secondPhrase.id = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        secondPhrase.name = "Basis B"
        project.phrases = [firstPhrase, secondPhrase].map {
            $0.synced(with: project.tracks, layers: project.layers)
        }
        project.selectedPhraseID = firstPhrase.id

        let documentBox = PhrasePerformOverlayDocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()

        return PhrasePerformOverlayFixture(
            session: session,
            engine: engine,
            documentBox: documentBox,
            trackID: trackID,
            trackIDs: project.tracks.map(\.id),
            muteLayerID: muteLayerID,
            sceneAID: sceneIDs[0],
            sceneBID: sceneIDs[1],
            phrases: project.phrases
        )
    }
}

@MainActor
private struct PhrasePerformOverlayFixture {
    let session: SequencerDocumentSession
    let engine: EngineController
    let documentBox: PhrasePerformOverlayDocumentBox
    let trackID: UUID
    let trackIDs: [UUID]
    let muteLayerID: String
    let sceneAID: UUID
    let sceneBID: UUID
    let phrases: [PhraseModel]

    func unregister() {
        SequencerDocumentSessionRegistry.unregister(session)
    }
}

@MainActor
private final class PhrasePerformOverlayDocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
