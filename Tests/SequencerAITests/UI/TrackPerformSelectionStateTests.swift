import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class TrackPerformSelectionStateTests: XCTestCase {
    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }
    }

    private func makeSession(project: Project) -> SequencerDocumentSession {
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
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
        return session
    }

    private func makeThreeTrackProject() -> Project {
        var project = makeLiveStoreProject().0
        project.appendTrack(trackType: .monoMelodic)
        project.appendTrack(trackType: .monoMelodic)
        return project
    }

    func test_selectedSet_addRemoveToggleClearAndReconcile() {
        let trackA = UUID()
        let trackB = UUID()
        let trackC = UUID()
        let removedTrack = UUID()
        var selection = TrackPerformSelectionState()

        selection.add(trackA)
        selection.add(trackB)
        XCTAssertEqual(selection.selectedTrackIDs, [trackA, trackB])
        XCTAssertTrue(selection.contains(trackA))

        selection.remove(trackA)
        XCTAssertEqual(selection.selectedTrackIDs, [trackB])

        selection.toggle(trackB)
        XCTAssertTrue(selection.isEmpty)

        selection.toggle(trackC)
        selection.add(removedTrack)
        selection.reconcile(availableTrackIDs: [trackA, trackB, trackC])
        XCTAssertEqual(selection.selectedTrackIDs, [trackC])

        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    func test_performLayerModesExposeTrackLayerSelectorInventory() {
        XCTAssertEqual(TrackPerformLayerMode.allCases, [.mute, .pattern, .fill, .noteRepeat, .stepOrder, .volume, .pan, .latch])
        XCTAssertEqual(TrackPerformLayerMode.mute.phraseLayerID, "mute")
        XCTAssertNil(TrackPerformLayerMode.mute.binaryControl)
        XCTAssertEqual(TrackPerformLayerMode.pattern.phraseLayerID, "pattern")
        XCTAssertNil(TrackPerformLayerMode.pattern.binaryControl)
        XCTAssertEqual(TrackPerformLayerMode.fill.phraseLayerID, "fill-flag")
        XCTAssertEqual(TrackPerformLayerMode.fill.binaryControl, .fill)
        XCTAssertNil(TrackPerformLayerMode.noteRepeat.phraseLayerID)
        XCTAssertEqual(TrackPerformLayerMode.noteRepeat.binaryControl, .noteRepeat)
        XCTAssertNil(TrackPerformLayerMode.stepOrder.phraseLayerID)
        XCTAssertNil(TrackPerformLayerMode.stepOrder.binaryControl)
        XCTAssertEqual(TrackPerformLayerMode.volume.phraseLayerID, "volume")
        XCTAssertNil(TrackPerformLayerMode.volume.binaryControl)
        XCTAssertNil(TrackPerformLayerMode.pan.phraseLayerID)
        XCTAssertNil(TrackPerformLayerMode.latch.phraseLayerID)
    }

    func test_performLayerModesExposeInlineVariantsOnFirstSelectionSurface() {
        XCTAssertEqual(TrackPerformLayerMode.pattern.inlineVariantLabels, (1...16).map { "P\($0)" })
        XCTAssertEqual(TrackPerformLayerMode.noteRepeat.inlineVariantLabels, ["Off", "1/4", "1/8", "1/16", "1/32", "Trip", "Roll", "Hold"])
        XCTAssertEqual(TrackPerformLayerMode.stepOrder.inlineVariantLabels, ["Off", "Identity", "Break Fold", "Back Half", "Reverse", "Skip 4", "Repeat 3", "Custom"])
        XCTAssertTrue(TrackPerformLayerMode.mute.inlineVariantLabels.isEmpty)
        XCTAssertTrue(TrackPerformLayerMode.volume.inlineVariantLabels.isEmpty)
    }

    func test_performanceLayerSelectionStateKeepsOnlyValidInlineVariants() {
        var selection = PerformanceLayerSelectionState(mode: .pattern, variantLabel: "P4")
        XCTAssertEqual(selection.mode, .pattern)
        XCTAssertEqual(selection.variantLabel, "P4")
        XCTAssertEqual(selection.activeLabel, "Pattern - P4")

        selection.select(.noteRepeat, variantLabel: "Roll")
        XCTAssertEqual(selection.mode, .noteRepeat)
        XCTAssertEqual(selection.variantLabel, "Roll")
        XCTAssertEqual(selection.activeLabel, "Note Repeat - Roll")

        selection.select(.volume, variantLabel: "Roll")
        XCTAssertEqual(selection.mode, .volume)
        XCTAssertNil(selection.variantLabel)
        XCTAssertEqual(selection.activeLabel, "Volume")

        selection.select(.stepOrder, variantLabel: "Missing")
        XCTAssertEqual(selection.mode, .stepOrder)
        XCTAssertNil(selection.variantLabel)
    }

    func test_performanceLayerSelectionStateSupportsTracksAndPhraseSurfaces() {
        var phraseSelection = PerformanceLayerSelectionState()
        XCTAssertEqual(phraseSelection.mode.phraseLayerID, "pattern")
        XCTAssertEqual(phraseSelection.activeLabel, "Pattern")

        phraseSelection.select(.stepOrder, variantLabel: "Break Fold")
        XCTAssertNil(phraseSelection.mode.phraseLayerID)
        XCTAssertEqual(phraseSelection.variantLabel, "Break Fold")
        XCTAssertEqual(phraseSelection.activeLabel, "Step Order - Break Fold")

        var tracksSelection = PerformanceLayerSelectionState(mode: .noteRepeat, variantLabel: "Roll")
        XCTAssertNil(tracksSelection.mode.phraseLayerID)
        XCTAssertEqual(tracksSelection.activeLabel, "Note Repeat - Roll")

        tracksSelection.select(.fill, variantLabel: "Roll")
        XCTAssertEqual(tracksSelection.mode.phraseLayerID, "fill-flag")
        XCTAssertNil(tracksSelection.variantLabel)
        XCTAssertEqual(tracksSelection.activeLabel, "Fill")
    }

    func test_authoredEditFromSelectedSourceFansOutToSelectedTracksOnly() throws {
        let project = makeThreeTrackProject()
        let session = makeSession(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let tracks = session.store.tracks.map(\.id)
        let sourceTrackID = tracks[0]
        let untouchedTrackID = tracks[1]
        let linkedTrackID = tracks[2]
        let muteLayerID = try XCTUnwrap(session.store.layers.first(where: { $0.target == .mute })?.id)
        var selection = TrackPerformSelectionState()
        selection.add(sourceTrackID)
        selection.add(linkedTrackID)

        let recipients = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: tracks,
            selection: selection
        )
        session.setPhraseCell(
            .single(.bool(true)),
            layerID: muteLayerID,
            trackIDs: recipients,
            phraseID: session.store.selectedPhraseID
        )

        let phrase = session.store.selectedPhrase
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: sourceTrackID), .single(.bool(true)))
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: linkedTrackID), .single(.bool(true)))
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: untouchedTrackID), .inheritDefault)
    }

    func test_authoredEditFromUnselectedSourceStaysLocal() throws {
        let project = makeThreeTrackProject()
        let session = makeSession(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let tracks = session.store.tracks.map(\.id)
        let selectedTrackID = tracks[0]
        let sourceTrackID = tracks[1]
        let otherSelectedTrackID = tracks[2]
        let muteLayerID = try XCTUnwrap(session.store.layers.first(where: { $0.target == .mute })?.id)
        let selection = TrackPerformSelectionState(selectedTrackIDs: [selectedTrackID, otherSelectedTrackID])

        let recipients = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: tracks,
            selection: selection
        )
        session.setPhraseCell(
            .single(.bool(true)),
            layerID: muteLayerID,
            trackIDs: recipients,
            phraseID: session.store.selectedPhraseID
        )

        let phrase = session.store.selectedPhrase
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: sourceTrackID), .single(.bool(true)))
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: selectedTrackID), .inheritDefault)
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: otherSelectedTrackID), .inheritDefault)
    }

    func test_authoredEditFromSingleSelectedSourceStaysLocal() throws {
        let project = makeThreeTrackProject()
        let session = makeSession(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let tracks = session.store.tracks.map(\.id)
        let sourceTrackID = tracks[0]
        let untouchedTrackID = tracks[1]
        let muteLayerID = try XCTUnwrap(session.store.layers.first(where: { $0.target == .mute })?.id)
        let selection = TrackPerformSelectionState(selectedTrackIDs: [sourceTrackID])

        let recipients = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: tracks,
            selection: selection
        )
        session.setPhraseCell(
            .single(.bool(true)),
            layerID: muteLayerID,
            trackIDs: recipients,
            phraseID: session.store.selectedPhraseID
        )

        let phrase = session.store.selectedPhrase
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: sourceTrackID), .single(.bool(true)))
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: untouchedTrackID), .inheritDefault)
    }

    func test_runtimeOverlay_setClearAndQueryArePerControlAndTrack() {
        let trackA = UUID()
        let trackB = UUID()
        var overlay = TrackPerformRuntimeOverlayState()

        overlay.setRuntime(true, control: .fill, trackIDs: [trackA, trackB])
        XCTAssertTrue(overlay.isActive(.fill, trackID: trackA))
        XCTAssertTrue(overlay.isActive(.fill, trackID: trackB))
        XCTAssertFalse(overlay.isActive(.noteRepeat, trackID: trackA))

        overlay.clearRuntime(control: .fill, trackIDs: [trackB])
        XCTAssertTrue(overlay.isActive(.fill, trackID: trackA))
        XCTAssertFalse(overlay.isActive(.fill, trackID: trackB))

        overlay.clearRuntime(control: .fill, trackIDs: [trackA])
        XCTAssertFalse(overlay.isActive(.fill, trackID: trackA))
    }

    func test_runtimeOverlay_latchModeIsSharedByFillAndNoteRepeat() {
        let trackA = UUID()
        let trackB = UUID()
        let orderedTrackIDs = [trackA, trackB]
        let selection = TrackPerformSelectionState(selectedTrackIDs: [trackA, trackB])
        var overlay = TrackPerformRuntimeOverlayState(latchMode: .latched)

        overlay.activate(
            control: .fill,
            sourceTrackID: trackA,
            orderedTrackIDs: orderedTrackIDs,
            selection: selection
        )
        overlay.activate(
            control: .noteRepeat,
            sourceTrackID: trackA,
            orderedTrackIDs: orderedTrackIDs,
            selection: selection
        )

        XCTAssertTrue(overlay.isLatched(.fill, trackID: trackA))
        XCTAssertTrue(overlay.isLatched(.fill, trackID: trackB))
        XCTAssertTrue(overlay.isLatched(.noteRepeat, trackID: trackA))
        XCTAssertTrue(overlay.isLatched(.noteRepeat, trackID: trackB))

        overlay.releaseMomentary(control: .fill, sourceTrackID: trackA)
        overlay.releaseMomentary(control: .noteRepeat, sourceTrackID: trackA)
        XCTAssertTrue(overlay.isActive(.fill, trackID: trackA))
        XCTAssertTrue(overlay.isActive(.noteRepeat, trackID: trackA))
    }

    func test_runtimeOverlay_unselectedSourceStaysLocal() {
        let selectedTrackID = UUID()
        let sourceTrackID = UUID()
        let otherSelectedTrackID = UUID()
        let orderedTrackIDs = [selectedTrackID, sourceTrackID, otherSelectedTrackID]
        let selection = TrackPerformSelectionState(selectedTrackIDs: [selectedTrackID, otherSelectedTrackID])
        var overlay = TrackPerformRuntimeOverlayState(latchMode: .latched)

        overlay.activate(
            control: .noteRepeat,
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: orderedTrackIDs,
            selection: selection
        )

        XCTAssertFalse(overlay.isActive(.noteRepeat, trackID: selectedTrackID))
        XCTAssertTrue(overlay.isActive(.noteRepeat, trackID: sourceTrackID))
        XCTAssertFalse(overlay.isActive(.noteRepeat, trackID: otherSelectedTrackID))
    }

    func test_runtimeOverlay_momentaryLifecycleUsesCapturedRecipients() {
        let sourceTrackID = UUID()
        let capturedTrackID = UUID()
        let laterSelectedTrackID = UUID()
        let orderedTrackIDs = [sourceTrackID, capturedTrackID, laterSelectedTrackID]
        var selection = TrackPerformSelectionState(selectedTrackIDs: [sourceTrackID, capturedTrackID])
        var overlay = TrackPerformRuntimeOverlayState(latchMode: .momentary)

        overlay.activate(
            control: .fill,
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: orderedTrackIDs,
            selection: selection
        )
        XCTAssertTrue(overlay.isMomentaryPressed(.fill, trackID: sourceTrackID))
        XCTAssertTrue(overlay.isMomentaryPressed(.fill, trackID: capturedTrackID))
        XCTAssertEqual(
            Set(overlay.momentaryRecipientTrackIDs(control: .fill, sourceTrackID: sourceTrackID)),
            [sourceTrackID, capturedTrackID]
        )

        selection.clear()
        selection.add(sourceTrackID)
        selection.add(laterSelectedTrackID)
        XCTAssertFalse(overlay.isMomentaryPressed(.fill, trackID: laterSelectedTrackID))

        overlay.releaseMomentary(control: .fill, sourceTrackID: sourceTrackID)
        XCTAssertFalse(overlay.isActive(.fill, trackID: sourceTrackID))
        XCTAssertFalse(overlay.isActive(.fill, trackID: capturedTrackID))
        XCTAssertFalse(overlay.isActive(.fill, trackID: laterSelectedTrackID))
    }

    func test_runtimeOverlay_canActivateExplicitMomentaryRecipientsForSupportedRepeatOnly() {
        let sourceTrackID = UUID()
        let supportedTrackID = UUID()
        let unsupportedTrackID = UUID()
        var overlay = TrackPerformRuntimeOverlayState(latchMode: .momentary)

        overlay.activate(
            control: .noteRepeat,
            sourceTrackID: sourceTrackID,
            recipientTrackIDs: [sourceTrackID, supportedTrackID]
        )

        XCTAssertTrue(overlay.isActive(.noteRepeat, trackID: sourceTrackID))
        XCTAssertTrue(overlay.isActive(.noteRepeat, trackID: supportedTrackID))
        XCTAssertFalse(overlay.isActive(.noteRepeat, trackID: unsupportedTrackID))
        XCTAssertEqual(
            Set(overlay.activeTrackIDs(.noteRepeat, orderedTrackIDs: [sourceTrackID, supportedTrackID, unsupportedTrackID])),
            [sourceTrackID, supportedTrackID]
        )
    }

    func test_runtimeOverlay_cleanupOnTeardownClearsLatchedAndMomentaryState() {
        let trackA = UUID()
        let trackB = UUID()
        var overlay = TrackPerformRuntimeOverlayState(latchMode: .latched)
        overlay.setRuntime(true, control: .fill, trackIDs: [trackA])

        overlay.latchMode = .momentary
        overlay.activate(
            control: .noteRepeat,
            sourceTrackID: trackB,
            orderedTrackIDs: [trackA, trackB],
            selection: TrackPerformSelectionState(selectedTrackIDs: [trackA, trackB])
        )

        XCTAssertTrue(overlay.isActive(.fill, trackID: trackA))
        XCTAssertTrue(overlay.isActive(.noteRepeat, trackID: trackB))

        overlay.cleanupRuntime()
        XCTAssertFalse(overlay.isActive(.fill, trackID: trackA))
        XCTAssertFalse(overlay.isActive(.noteRepeat, trackID: trackB))
    }

    func test_runtimeOverlay_doesNotPersistIntoPhraseCellData() throws {
        let project = makeThreeTrackProject()
        let session = makeSession(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let tracks = session.store.tracks.map(\.id)
        let fillLayerID = try XCTUnwrap(session.store.layers.first(where: { $0.id == "fill-flag" })?.id)
        let patternLayerID = try XCTUnwrap(session.store.layers.first(where: { $0.id == "pattern" })?.id)
        var overlay = TrackPerformRuntimeOverlayState(latchMode: .latched)
        let selection = TrackPerformSelectionState(selectedTrackIDs: [tracks[0], tracks[2]])

        overlay.activate(
            control: .fill,
            sourceTrackID: tracks[0],
            orderedTrackIDs: tracks,
            selection: selection
        )
        overlay.activate(
            control: .noteRepeat,
            sourceTrackID: tracks[0],
            orderedTrackIDs: tracks,
            selection: selection
        )

        let phrase = session.store.selectedPhrase
        XCTAssertTrue(overlay.isActive(.fill, trackID: tracks[0]))
        XCTAssertTrue(overlay.isActive(.noteRepeat, trackID: tracks[2]))
        XCTAssertEqual(phrase.cell(for: fillLayerID, trackID: tracks[0]), .inheritDefault)
        XCTAssertEqual(phrase.cell(for: fillLayerID, trackID: tracks[1]), .inheritDefault)
        XCTAssertEqual(phrase.cell(for: fillLayerID, trackID: tracks[2]), .inheritDefault)
        XCTAssertEqual(phrase.cell(for: patternLayerID, trackID: tracks[0]), .inheritDefault)
        XCTAssertEqual(phrase.cell(for: patternLayerID, trackID: tracks[2]), .inheritDefault)
    }
}
