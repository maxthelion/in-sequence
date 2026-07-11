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

    private func makeSessionWithEngine(project: Project) -> (SequencerDocumentSession, EngineController) {
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        return (session, engine)
    }

    private func startEngineForManualTicks(_ engine: EngineController) {
        engine.start()
        engine.clock.stop()
    }

    private func makeThreeTrackProject() -> Project {
        var project = makeLiveStoreProject().0
        project.appendTrack(trackType: .monoMelodic)
        project.appendTrack(trackType: .monoMelodic)
        return project
    }

    private func makeTrack(name: String = "Track") -> StepSequenceTrack {
        StepSequenceTrack(
            name: name,
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: Array(repeating: false, count: 16),
            velocity: 100,
            gateLength: 4
        )
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
        XCTAssertEqual(TrackPerformLayerMode.allCases, [.mute, .pattern, .fill, .noteRepeat, .stepOrder, .volume, .pan])
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
        XCTAssertNil(TrackPerformLayerMode.volume.phraseLayerID)
        XCTAssertNil(TrackPerformLayerMode.volume.binaryControl)
        XCTAssertNil(TrackPerformLayerMode.pan.phraseLayerID)
    }

    func test_performLayerModesExposeInlineVariantsOnFirstSelectionSurface() {
        XCTAssertTrue(TrackPerformLayerMode.pattern.inlineVariantLabels.isEmpty)
        XCTAssertEqual(TrackPerformLayerMode.noteRepeat.inlineVariantLabels, ["1/4", "1/8", "1/16", "1/32", "1/64"])
        XCTAssertEqual(TrackPerformLayerMode.stepOrder.inlineVariantLabels, ["Identity", "Break Fold", "Back Half", "Reverse", "Skip 4", "Repeat 3", "Custom"])
        XCTAssertTrue(TrackPerformLayerMode.mute.inlineVariantLabels.isEmpty)
        XCTAssertTrue(TrackPerformLayerMode.volume.inlineVariantLabels.isEmpty)
    }

    func testTrackPerformPatternMiniCellSelectsExactSlot() {
        let selectedSlot = TrackPerformPatternMiniCellInteraction.selectedSlotAfterMiniCellClick(
            requestedSlotIndex: 3
        )

        XCTAssertEqual(selectedSlot, 3)
    }

    func testTrackPerformPatternMiniCellRepeatedClickDoesNotCycle() {
        let selectedSlot = TrackPerformPatternMiniCellInteraction.selectedSlotAfterMiniCellClick(
            requestedSlotIndex: 3
        )

        XCTAssertEqual(selectedSlot, 3)
    }

    func testTrackPerformPatternMiniCellUnavailableSlotIsInert() {
        let selectedSlot = TrackPerformPatternMiniCellInteraction.selectedSlotAfterMiniCellClick(
            requestedSlotIndex: TrackPatternBank.slotCount
        )

        XCTAssertNil(selectedSlot)
    }

    func testTrackPerformPatternMiniCellExplicitSlotCanArmQuantisedPatternChange() throws {
        let project = makeThreeTrackProject()
        let (session, engine) = makeSessionWithEngine(project: project)
        defer {
            engine.stop()
            SequencerDocumentSessionRegistry.unregister(session)
        }
        session.workspaceMode = .perform
        startEngineForManualTicks(engine)

        let trackID = session.store.tracks[0].id
        let phrase = session.store.selectedPhrase
        let requestedSlot = try XCTUnwrap(TrackPerformPatternMiniCellInteraction.selectedSlotAfterMiniCellClick(
            requestedSlotIndex: 3
        ))

        session.selectQuantisedPatternIndex(
            slotIndex: requestedSlot,
            trackIDs: [trackID],
            basisPhrase: phrase
        )

        XCTAssertEqual(
            engine.quantisedPendingChanges,
            [.pattern(trackID: trackID, slotIndex: 3, basisPhraseID: phrase.id, lengthBars: nil, startTick: nil)],
            "P4 mini-cell selection must arm exactly P4 through the shared quantised pattern route"
        )
        XCTAssertNil(
            session.performOverlayCell(phraseID: phrase.id, layerID: TrackPerformLayerMode.pattern.phraseLayerID!, trackID: trackID),
            "Q:BAR arming should not stage the overlay until the boundary commit"
        )
    }

    func testTrackPerformPatternMiniCellImmediatePathStagesExactSlotWhenQuantiseOff() throws {
        let project = makeThreeTrackProject()
        let (session, engine) = makeSessionWithEngine(project: project)
        defer {
            engine.stop()
            SequencerDocumentSessionRegistry.unregister(session)
        }
        session.workspaceMode = .perform
        session.performQuantise = .off
        startEngineForManualTicks(engine)

        let trackID = session.store.tracks[0].id
        let phrase = session.store.selectedPhrase
        let patternLayerID = try XCTUnwrap(TrackPerformLayerMode.pattern.phraseLayerID)
        let requestedSlot = try XCTUnwrap(TrackPerformPatternMiniCellInteraction.selectedSlotAfterMiniCellClick(
            requestedSlotIndex: 3
        ))

        session.setPhraseCell(
            .single(.index(requestedSlot)),
            layerID: patternLayerID,
            trackIDs: [trackID],
            phraseID: phrase.id
        )

        XCTAssertTrue(engine.quantisedPendingChanges.isEmpty)
        XCTAssertEqual(
            session.performOverlayCell(phraseID: phrase.id, layerID: patternLayerID, trackID: trackID),
            .single(.index(3)),
            "Q:OFF mini-cell selection stays immediate and exact"
        )
    }

    func testTrackPerformPatternCardBackgroundDoesNotCyclePattern() {
        let track = makeTrack()
        let patternLayer = PhraseLayerDefinition.defaultSet(for: [track])
            .first { $0.id == TrackPerformLayerMode.pattern.phraseLayerID }!
        let muteLayer = PhraseLayerDefinition.defaultSet(for: [track])
            .first { $0.id == TrackPerformLayerMode.mute.phraseLayerID }!

        XCTAssertFalse(TrackPerformPatternMiniCellInteraction.shouldCycleFromCardBackground(layer: patternLayer))
        XCTAssertTrue(TrackPerformPatternMiniCellInteraction.shouldCycleFromCardBackground(layer: muteLayer))
    }

    func test_performanceLayerOptionsFlattenVariantsIntoFullCells() {
        let options = PerformanceLayerOption.all
        XCTAssertTrue(options.contains(PerformanceLayerOption(mode: .pattern, variantLabel: nil)))
        XCTAssertTrue(options.contains(PerformanceLayerOption(mode: .noteRepeat, variantLabel: "1/16")))
        XCTAssertTrue(options.contains(PerformanceLayerOption(mode: .stepOrder, variantLabel: "Break Fold")))
        XCTAssertFalse(options.contains(PerformanceLayerOption(mode: .noteRepeat, variantLabel: nil)))
        let plainModes = options.filter { $0.variantLabel == nil }.map(\.mode)
        XCTAssertEqual(plainModes, [.mute, .pattern, .fill, .volume, .pan])
    }

    func test_patternValueOptionsExposeEveryExactSlot() {
        let options = PerformanceLayerOption.patternValues

        XCTAssertEqual(options.count, TrackPatternBank.slotCount)
        XCTAssertEqual(options.map(\.title), (1...TrackPatternBank.slotCount).map { "P\($0)" })
        XCTAssertEqual(options.compactMap(\.patternSlotIndex), Array(0..<TrackPatternBank.slotCount))
        XCTAssertNil(PerformanceLayerOption(mode: .pattern, variantLabel: "P17").patternSlotIndex)
        XCTAssertNil(PerformanceLayerOption(mode: .pattern, variantLabel: nil).patternSlotIndex)
    }

    func test_globalApplyValueVisibilityCollapsesToCurrentAndPinnedValues() {
        let options = PerformanceLayerOption.patternValues
        var state = GlobalApplyValueVisibilityState()

        XCTAssertEqual(
            state.visibleOptions(for: .pattern, allOptions: options, currentOption: options[3]),
            [options[3]]
        )

        state.togglePinned(options[0])
        state.togglePinned(options[1])
        state.togglePinned(options[2])
        XCTAssertEqual(
            state.visibleOptions(for: .pattern, allOptions: options, currentOption: options[3]),
            [options[3], options[0], options[1], options[2]]
        )

        state.togglePinned(options[1])
        XCTAssertEqual(
            state.visibleOptions(for: .pattern, allOptions: options, currentOption: options[3]),
            [options[3], options[0], options[2]]
        )
    }

    func test_globalApplyValueVisibilityExpansionShowsEveryValueAndRetainsPins() {
        let options = PerformanceLayerOption.patternValues
        var state = GlobalApplyValueVisibilityState()
        state.togglePinned(options[2])
        state.toggleExpanded(.pattern)

        XCTAssertTrue(state.isExpanded(.pattern))
        XCTAssertTrue(state.isPinned(options[2]))
        XCTAssertEqual(
            state.visibleOptions(for: .pattern, allOptions: options, currentOption: options[0]),
            options
        )

        state.toggleExpanded(.pattern)
        XCTAssertFalse(state.isExpanded(.pattern))
        XCTAssertEqual(
            state.visibleOptions(for: .pattern, allOptions: options, currentOption: options[0]),
            [options[0], options[2]]
        )
    }

    func test_globalApplyValueVisibilityDoesNotPinUnavailableValues() {
        var state = GlobalApplyValueVisibilityState()
        state.togglePinned(.unavailableStepOrder)

        XCTAssertFalse(state.isPinned(.unavailableStepOrder))
    }

    func test_phrasePerformanceOptionsExposeOnlyBackedLayersAndRuntimeToggles() {
        let validMap = StepOrderMap(name: "Break Fold")
        let invalidMap = StepOrderMap(name: "Broken", values: [0, 1])

        let options = PerformanceLayerOption.phraseOptions(
            availableLayerIDs: ["mute", "pattern", "fill-flag"],
            stepOrderMaps: [validMap, invalidMap],
            phraseStepCount: StepOrderMap.stepCount
        )

        XCTAssertTrue(options.contains(PerformanceLayerOption(mode: .mute, variantLabel: nil)))
        XCTAssertTrue(options.contains(PerformanceLayerOption(mode: .noteRepeat, variantLabel: "1/32")))
        XCTAssertTrue(options.contains(PerformanceLayerOption(mode: .stepOrder, variantLabel: "Break Fold")))
        XCTAssertFalse(options.contains(PerformanceLayerOption(mode: .stepOrder, variantLabel: "Broken")))
        XCTAssertFalse(options.contains { $0.mode == .volume || $0.mode == .pan })
    }

    func test_phrasePerformanceOptionsExposeMaterializableIdentityWhenNoStepOrderMapsExist() throws {
        let options = PerformanceLayerOption.phraseOptions(
            availableLayerIDs: ["mute", "pattern", "fill-flag"],
            stepOrderMaps: [],
            phraseStepCount: StepOrderMap.stepCount
        )

        let option = try XCTUnwrap(options.first { $0.mode == .stepOrder })
        XCTAssertEqual(option, .implicitIdentityStepOrder)
        XCTAssertNil(option.resolvedStepOrderMap(in: []))

        let materialized = try XCTUnwrap(option.materializedStepOrderMap(in: []))
        XCTAssertEqual(materialized.name, "Identity")
        XCTAssertEqual(materialized.values, StepOrderMap.identityValues)
        XCTAssertTrue(materialized.isValid)
    }

    func test_phrasePerformanceStepOrderOptionResolvesExistingMapWithoutDuplicatingIt() throws {
        let map = StepOrderMap(name: "Break Fold", values: [3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0])
        let option = PerformanceLayerOption(mode: .stepOrder, variantLabel: map.name)

        XCTAssertEqual(option.resolvedStepOrderMap(in: [map]), map)
        XCTAssertEqual(option.materializedStepOrderMap(in: [map]), map)
    }

    func test_phrasePerformanceOptionsExposeUnavailableStepOrderWhenPhraseLengthIsUnsupported() throws {
        let options = PerformanceLayerOption.phraseOptions(
            availableLayerIDs: ["mute"],
            stepOrderMaps: [StepOrderMap(name: "Identity")],
            phraseStepCount: StepOrderMap.stepCount * 2
        )

        let option = try XCTUnwrap(options.first { $0.mode == .stepOrder })
        XCTAssertEqual(option, .unavailableStepOrder)
        XCTAssertFalse(option.isAvailable)
        XCTAssertEqual(option.unavailableReason, "16 steps only")
        XCTAssertTrue(options.contains { $0.mode == .noteRepeat })
    }

    func test_performanceLayerSelectionStateKeepsOnlyValidInlineVariants() {
        var selection = PerformanceLayerSelectionState(mode: .pattern, variantLabel: "P4")
        XCTAssertEqual(selection.mode, .pattern)
        XCTAssertNil(selection.variantLabel)
        XCTAssertEqual(selection.activeLabel, "Pattern")

        selection.select(.noteRepeat, variantLabel: "1/8")
        XCTAssertEqual(selection.mode, .noteRepeat)
        XCTAssertEqual(selection.variantLabel, "1/8")
        XCTAssertEqual(selection.activeLabel, "Note Repeat - 1/8")

        selection.select(.volume, variantLabel: "1/8")
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

        var tracksSelection = PerformanceLayerSelectionState(mode: .noteRepeat, variantLabel: "1/32")
        XCTAssertNil(tracksSelection.mode.phraseLayerID)
        XCTAssertEqual(tracksSelection.activeLabel, "Note Repeat - 1/32")

        tracksSelection.select(.fill, variantLabel: "1/32")
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
