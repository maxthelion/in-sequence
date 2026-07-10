import XCTest
import SwiftUI
@testable import SequencerAI

// MARK: - Kit matrix as a grouped step editor
//
// Store/engine coverage for the Part 3 rework:
//   - matrix step toggles and layer edits produce the SAME mutations as the
//     single-track editor (shared `ClipNoteGridStepEditing` transforms +
//     the same `ensureClipAndMutate` typed session mutation);
//   - matrix render/read paths never call `exportToProject`
//     (`assertNoExportDuring` guard);
//   - the group pattern row fan-out matches N individual pattern switches;
//   - Apply Template is one batched, atomic document mutation.

@MainActor
final class DrumKitMatrixEditingTests: XCTestCase {

    func test_templateTargetSelection_promptsReplacesAndAdds() {
        var selection = DrumKitPatternTargetSelection()

        XCTAssertFalse(selection.requestTemplateChooser())
        XCTAssertTrue(selection.isPrompting)

        selection.select(slotIndex: 2, additive: false)
        XCTAssertEqual(selection.slotIndexes, [2])
        XCTAssertFalse(selection.isPrompting)
        XCTAssertTrue(selection.requestTemplateChooser())

        selection.select(slotIndex: 5, additive: true)
        XCTAssertEqual(selection.slotIndexes, [2, 5])

        selection.select(slotIndex: 5, additive: true)
        XCTAssertEqual(selection.slotIndexes, [2])

        selection.select(slotIndex: 1, additive: false)
        XCTAssertEqual(selection.slotIndexes, [1])

        selection.select(slotIndex: 1, additive: false)
        XCTAssertTrue(selection.slotIndexes.isEmpty)

        selection.clear()
        XCTAssertTrue(selection.slotIndexes.isEmpty)
        XCTAssertFalse(selection.isPrompting)
    }

    func test_fillPresentation_fallsBackToNormalWhenUnavailable() {
        XCTAssertFalse(
            DrumKitFillModePresentation(isAvailable: false, requestedFill: true).isFillSelected
        )
        XCTAssertTrue(
            DrumKitFillModePresentation(isAvailable: true, requestedFill: true).isFillSelected
        )
    }

    func test_matrixLayerMenuExposesEveryEditableLayerInOrder() {
        XCTAssertEqual(DrumKitMatrixLayer.allCases.map(\.title), ["Steps", "Velocity", "Length", "Chance"])
    }

    func test_visualCommandParsesDeterministicStepSelection() {
        XCTAssertEqual(
            DrumKitVisualCommand(rawValue: "select-step:0:2"),
            .selectStep(memberIndex: 0, stepIndex: 2)
        )
        XCTAssertNil(DrumKitVisualCommand(rawValue: "select-step:bad:2"))
    }

    func test_stepClipboardPasteMapsOnlyToSelectedWritableSteps() {
        let first = StepClipboardEntry(
            active: true,
            velocity: 96,
            length: .steps(2),
            chance: 0.75,
            macroOverrides: [:],
            sliceIndex: nil,
            sliceMode: nil
        )
        let second = StepClipboardEntry(
            active: false,
            velocity: nil,
            length: .natural,
            chance: nil,
            macroOverrides: [:],
            sliceIndex: nil,
            sliceMode: nil
        )
        let clipboard = StepClipboard(
            sourceClipID: UUID(),
            steps: [1: first, 6: second]
        )

        let destinations = DrumKitStepClipboardTransfer.destinations(
            clipboard: clipboard,
            selectedStepIndexes: [3, 7, 99],
            writableStepIndexes: 0..<8
        )

        XCTAssertEqual(destinations.map(\.stepIndex), [3, 7])
        XCTAssertEqual(destinations.map(\.entry), [first, second])
        XCTAssertFalse(destinations.contains(where: { $0.stepIndex == 99 }))
    }

    // MARK: - Helpers

    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }

        var binding: Binding<SeqAIDocument> {
            Binding(
                get: { self.document },
                set: { self.document = $0 }
            )
        }
    }

    private func makeSession() -> (SequencerDocumentSession, DocumentBox) {
        let (project, _, _) = makeLiveStoreProject()
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        return (session, box)
    }

    @discardableResult
    private func makeDrumGroup(
        in session: SequencerDocumentSession,
        templateID: UUID? = nil
    ) -> TrackGroupID {
        let plan = DrumGroupPlan(
            name: "Matrix Kit",
            color: "#C06030",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick"),
                DrumGroupPlan.Member(tag: "snare", trackName: "Snare"),
                DrumGroupPlan.Member(tag: "hat-closed", trackName: "Hat"),
            ],
            templateID: templateID
        )
        guard let groupID = session.addDrumGroup(plan: plan) else {
            XCTFail("addDrumGroup failed")
            return TrackGroupID()
        }
        return groupID
    }

    private func matrixModel(
        _ session: SequencerDocumentSession,
        groupID: TrackGroupID,
        displayStepCount: Int = 16
    ) -> DrumKitMatrixModel? {
        guard let originatingPartID = session.store.trackGroups
            .first(where: { $0.id == groupID })?.memberIDs.first
        else {
            return nil
        }
        return DrumKitMatrixModel(
            groupID: groupID,
            originatingPartID: originatingPartID,
            displayStepCount: displayStepCount,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups,
            layers: session.store.layers,
            selectedPhrase: session.store.selectedPhrase,
            patternBanks: Array(session.store.patternBanksByTrackID.values),
            clipPool: session.store.clipPool,
            generatorPool: session.store.generatorPool
        )
    }

    private func slotContent(
        _ session: SequencerDocumentSession,
        trackID: UUID,
        slotIndex: Int
    ) -> ClipContent? {
        let clipID = session.store.patternBank(for: trackID).slot(at: slotIndex).sourceRef.clipID
        return session.store.clipEntry(id: clipID)?.content.normalized
    }

    /// Commit content through the matrix edit path: the same
    /// `ensureClipAndMutate` typed mutation the single-track editor's
    /// `updateClipContent` uses.
    private func commitMatrixEdit(
        _ session: SequencerDocumentSession,
        row: DrumKitMatrixModel.Row,
        content: ClipContent
    ) {
        session.ensureClipAndMutate(
            at: PatternSlotAddress(trackID: row.memberID, slotIndex: row.patternSlotIndex)
        ) { _, entry in
            entry.content = content
        }
    }

    /// The single-track editor's edit semantics: `ClipContentPreview` builds
    /// the toggle with `ClipNoteGridStepEditing` (lane `.main`, the
    /// track-derived default note) and commits it in place through
    /// `StepGridCoordinator.commitEdit` → `session.mutateClip(id:)`.
    private func singleTrackToggle(
        _ session: SequencerDocumentSession,
        trackID: UUID,
        stepIndex: Int
    ) {
        guard let track = session.store.tracks.first(where: { $0.id == trackID }) else {
            return XCTFail("missing track")
        }
        session.setSelectedTrackID(trackID)
        let slotIndex = session.store.selectedPatternIndex(for: trackID)
        let address = PatternSlotAddress(trackID: trackID, slotIndex: slotIndex)
        let current = slotContent(session, trackID: trackID, slotIndex: slotIndex)
            ?? .emptyNoteGrid(lengthSteps: 16)
        guard case let .noteGrid(lengthSteps, steps) = current else {
            return XCTFail("expected note grid")
        }
        let defaultNote = ClipStepNote(
            pitch: track.pitches.first ?? 60,
            velocity: track.velocity,
            lengthSteps: track.gateLength
        ).normalized
        let updated = ClipNoteGridStepEditing.togglingStep(
            at: stepIndex,
            lengthSteps: lengthSteps,
            steps: steps,
            lane: .main,
            defaultNote: defaultNote
        )
        session.ensureClipAndMutate(at: address) { _, entry in
            entry.content = updated
        }
    }

    // MARK: - Matrix edits == single-track edits

    func test_matrixToggle_producesSameMutationAsSingleTrackEditor() throws {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let model = try XCTUnwrap(matrixModel(session, groupID: groupID))
        let row = try XCTUnwrap(model.rows.first)
        let original = slotContent(session, trackID: row.memberID, slotIndex: row.patternSlotIndex)

        // Toggle step 3 through the matrix path.
        guard case let .editable(_, lengthSteps, steps) = row.content else {
            return XCTFail("expected editable row")
        }
        let matrixContent = try XCTUnwrap(
            DrumKitMatrixStepEdit.tappedContent(
                layer: .steps,
                lane: .main,
                stepIndex: 3,
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: row.defaultNote
            )
        )
        commitMatrixEdit(session, row: row, content: matrixContent)
        let afterMatrixToggle = try XCTUnwrap(slotContent(session, trackID: row.memberID, slotIndex: row.patternSlotIndex))
        XCTAssertNotEqual(afterMatrixToggle, original)

        // Toggle the same step back through the matrix path — round trip.
        let refreshedRow = try XCTUnwrap(matrixModel(session, groupID: groupID)?.rows.first)
        guard case let .editable(_, l2, s2) = refreshedRow.content else {
            return XCTFail("expected editable row")
        }
        let revertContent = try XCTUnwrap(
            DrumKitMatrixStepEdit.tappedContent(
                layer: .steps,
                lane: .main,
                stepIndex: 3,
                lengthSteps: l2,
                steps: s2,
                defaultNote: refreshedRow.defaultNote
            )
        )
        commitMatrixEdit(session, row: refreshedRow, content: revertContent)
        XCTAssertEqual(
            slotContent(session, trackID: row.memberID, slotIndex: row.patternSlotIndex),
            original,
            "Matrix toggle round-trips to the original content"
        )

        // Now the same toggle through the single-track editor path.
        singleTrackToggle(session, trackID: row.memberID, stepIndex: 3)
        let afterSingleTrackToggle = slotContent(session, trackID: row.memberID, slotIndex: row.patternSlotIndex)
        XCTAssertEqual(
            afterSingleTrackToggle,
            afterMatrixToggle,
            "A matrix toggle is byte-for-byte the same mutation as a single-track toggle"
        )
    }

    func test_matrixVelocityAndChanceEdits_matchSingleTrackTransforms() throws {
        let (session, _) = makeSession()
        let template = DrumKitFixtures.factoryTemplate(named: "808")
        let groupID = makeDrumGroup(in: session, templateID: template.id)
        let model = try XCTUnwrap(matrixModel(session, groupID: groupID))
        let row = try XCTUnwrap(model.rows.first)

        guard case let .editable(_, lengthSteps, steps) = row.content else {
            return XCTFail("expected editable row")
        }
        XCTAssertNotNil(steps[0].main, "templated kick has step 1 active")

        // Velocity tap cycles through the same allowed values as the
        // single-track editor (ClipContentPreview's velocity layer).
        let velocityTapped = try XCTUnwrap(
            DrumKitMatrixStepEdit.tappedContent(
                layer: .velocity,
                lane: .main,
                stepIndex: 0,
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: row.defaultNote
            )
        )
        let expectedVelocity = ClipNoteGridStepEditing.updatingLaneVelocities(
            lane: .main,
            values: [
                ClipNoteGridStepEditing.cycledValue(
                    after: ClipNoteGridStepEditing.velocityValue(for: steps[0], lane: .main),
                    allowedValues: ClipNoteGridStepEditing.velocityCycleValues
                ),
            ],
            visibleIndices: [0],
            lengthSteps: lengthSteps,
            steps: steps,
            defaultNote: row.defaultNote
        )
        XCTAssertEqual(velocityTapped, expectedVelocity)

        commitMatrixEdit(session, row: row, content: velocityTapped)
        let stored = try XCTUnwrap(slotContent(session, trackID: row.memberID, slotIndex: row.patternSlotIndex))
        XCTAssertEqual(stored, velocityTapped.normalized)

        // Velocity drag writes the same absolute fraction as a single-track drag.
        let dragged = try XCTUnwrap(
            DrumKitMatrixStepEdit.draggedContent(
                layer: .velocity,
                lane: .main,
                stepIndex: 0,
                fraction: 0.5,
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: row.defaultNote
            )
        )
        guard case let .noteGrid(_, draggedSteps) = dragged.normalized else {
            return XCTFail("expected note grid")
        }
        XCTAssertEqual(draggedSteps[0].main?.notes.first?.velocity, 64)

        let lengthTapped = try XCTUnwrap(
            DrumKitMatrixStepEdit.tappedContent(
                layer: .length,
                lane: .main,
                stepIndex: 0,
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: row.defaultNote
            )
        )
        guard case let .noteGrid(_, lengthEditedSteps) = lengthTapped.normalized else {
            return XCTFail("expected note grid")
        }
        let originalLength = steps[0].main?.notes.first?.lengthSteps
        let expectedLength = ClipNoteGridStepEditing.nextLength(
            after: originalLength,
            allowsNatural: false
        )
        XCTAssertEqual(lengthEditedSteps[0].main?.notes.first?.lengthSteps, expectedLength)

        // Chance tap cycles the shared chance values.
        let chanceTapped = try XCTUnwrap(
            DrumKitMatrixStepEdit.tappedContent(
                layer: .chance,
                lane: .main,
                stepIndex: 0,
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: row.defaultNote
            )
        )
        let expectedChance = ClipNoteGridStepEditing.updatingLaneChances(
            lane: .main,
            values: [
                ClipNoteGridStepEditing.cycledValue(
                    after: ClipNoteGridStepEditing.chanceValue(for: steps[0], lane: .main),
                    allowedValues: ClipNoteGridStepEditing.chanceCycleValues
                ),
            ],
            visibleIndices: [0],
            lengthSteps: lengthSteps,
            steps: steps,
            defaultNote: row.defaultNote
        )
        XCTAssertEqual(chanceTapped, expectedChance)
    }

    func test_generatorBackedRow_hasNoEditableContent() throws {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let memberID = try XCTUnwrap(
            session.store.trackGroups.first(where: { $0.id == groupID })?.memberIDs.first
        )
        _ = session.createBlankGeneratorSource(trackID: memberID, slotIndex: 0)

        let model = try XCTUnwrap(matrixModel(session, groupID: groupID))
        let row = try XCTUnwrap(model.rows.first(where: { $0.memberID == memberID }))

        XCTAssertFalse(row.isEditable, "Generator-backed slots render read-only cells")
        guard case .generator = row.content else {
            return XCTFail("expected generator content")
        }
    }

    // MARK: - No exportToProject in matrix render paths

    func test_matrixModelConstruction_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)

        assertNoExportDuring(session.store) {
            let model = matrixModel(session, groupID: groupID, displayStepCount: 16)
            XCTAssertNotNil(model)
            // The row read paths a render pass touches.
            for row in model?.rows ?? [] {
                _ = row.isEditable
                _ = row.patternBadge
                if case let .editable(_, _, steps) = row.content {
                    for step in steps {
                        _ = ClipNoteGridStepEditing.visualState(for: step, lane: .main)
                        _ = ClipNoteGridStepEditing.velocityValue(for: step, lane: .main)
                        _ = ClipNoteGridStepEditing.chanceValue(for: step, lane: .main)
                    }
                }
            }
            _ = model?.groupSelectedSlotIndex
            _ = model?.occupiedSlotIndexes
        }
    }

    // MARK: - Group pattern row fan-out

    func test_groupPatternRowFanOut_matchesIndividualSwitches() throws {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let memberIDs = try XCTUnwrap(
            session.store.trackGroups.first(where: { $0.id == groupID })?.memberIDs
        )

        // Fan-out: every member realigns to slot 5. (Patterns are global, so a
        // single slot selection writes the same index to every member.)
        session.setDrumGroupSelectedPatternIndex(4, groupID: groupID)
        let fannedOut = session.store.exportToProject()
        for memberID in memberIDs {
            XCTAssertEqual(fannedOut.selectedPatternIndex(for: memberID), 4)
        }
        XCTAssertEqual(matrixModel(session, groupID: groupID)?.groupSelectedSlotIndex, 4)

        // The fan-out is exactly N individual switches: reset, switch each
        // member individually, and compare the resulting phrase state.
        session.setDrumGroupSelectedPatternIndex(0, groupID: groupID)
        for memberID in memberIDs {
            session.setSelectedPatternIndex(4, for: memberID)
        }
        let individually = session.store.exportToProject()
        XCTAssertEqual(individually.phrases, fannedOut.phrases)
    }

    func test_groupPatternRowFanOut_doesNotTouchNonMembers() throws {
        let (session, _) = makeSession()
        let outsiderID = session.store.selectedTrackID
        let groupID = makeDrumGroup(in: session)

        session.setDrumGroupSelectedPatternIndex(7, groupID: groupID)

        XCTAssertEqual(
            session.store.exportToProject().selectedPatternIndex(for: outsiderID),
            0,
            "Fan-out only switches group members"
        )
    }

    func test_kitCaptureSave_writesEveryMemberToChosenPatternSlot() throws {
        let (session, _) = makeSession()
        let outsiderID = session.store.selectedTrackID
        let groupID = makeDrumGroup(in: session)
        let memberIDs = try XCTUnwrap(
            session.store.trackGroups.first(where: { $0.id == groupID })?.memberIDs
        )
        let destinationSlot = 5

        for (memberOffset, memberID) in memberIDs.enumerated() {
            let clipID = session.saveMaterializedClipToPatternSlot(
                trackID: memberID,
                slotIndex: destinationSlot,
                content: Self.captureContent(memberOffset: memberOffset),
                name: "Kit Capture P\(destinationSlot + 1)"
            )
            XCTAssertNotNil(clipID)
        }

        let model = try XCTUnwrap(matrixModel(session, groupID: groupID))
        XCTAssertTrue(model.occupiedSlotIndexes.contains(destinationSlot))

        for (memberOffset, memberID) in memberIDs.enumerated() {
            let content = try XCTUnwrap(slotContent(session, trackID: memberID, slotIndex: destinationSlot))
            guard case let .noteGrid(lengthSteps, steps) = content else {
                return XCTFail("expected note-grid capture for kit member")
            }
            XCTAssertEqual(lengthSteps, 16)
            XCTAssertEqual(steps[memberOffset].main?.notes.first?.pitch, 60 + memberOffset)
        }

        XCTAssertNil(
            session.store.patternBank(for: outsiderID).slot(at: destinationSlot).sourceRef.clipID,
            "Kit capture save must only write kit members"
        )
    }

    // MARK: - Apply Template: one batched, atomic mutation

    func test_applyPatternTemplate_isOneAtomicDocumentMutation() throws {
        let (session, box) = makeSession()
        let template = DrumKitFixtures.factoryTemplate(named: "808")
        let groupID = makeDrumGroup(in: session)
        let memberIDs = try XCTUnwrap(
            session.store.trackGroups.first(where: { $0.id == groupID })?.memberIDs
        )
        session.flushToDocumentSync()
        let documentBefore = box.document.project

        let changed = session.applyPatternTemplate(template, toGroup: groupID, slotIndex: 0)
        XCTAssertTrue(changed)
        XCTAssertEqual(
            box.document.project,
            documentBefore,
            "The batch must not write the document mid-apply (debounced flush pending)"
        )

        // One flush lands the WHOLE apply as a single document transition —
        // the batch is the undo unit; no member-by-member intermediate states.
        session.flushToDocumentSync()
        let documentAfter = box.document.project
        XCTAssertNotEqual(documentAfter, documentBefore)
        for (memberID, tag) in zip(memberIDs, ["kick", "snare", "hat-closed"]) {
            let clipID = documentAfter.patternBank(for: memberID).slot(at: 0).sourceRef.clipID
            let clip = try XCTUnwrap(documentAfter.clipPool.first(where: { $0.id == clipID }))
            XCTAssertEqual(
                noteGridMainStepPattern(clip.content),
                template.patterns[tag],
                "All matched members land together in the single write"
            )
        }

        // Same matching behavior as the shared Project implementation.
        XCTAssertEqual(
            noteGridMainStepPattern(try XCTUnwrap(slotContent(session, trackID: memberIDs[0], slotIndex: 0))),
            template.patterns["kick"]
        )
        XCTAssertEqual(
            noteGridMainStepPattern(try XCTUnwrap(slotContent(session, trackID: memberIDs[1], slotIndex: 0))),
            template.patterns["snare"]
        )
        XCTAssertEqual(
            noteGridMainStepPattern(try XCTUnwrap(slotContent(session, trackID: memberIDs[2], slotIndex: 0))),
            template.patterns["hat-closed"]
        )
    }

    func test_applyPatternTemplate_skipsGeneratorSlots() throws {
        let (session, _) = makeSession()
        let template = DrumKitFixtures.factoryTemplate(named: "808")
        let groupID = makeDrumGroup(in: session)
        let memberIDs = try XCTUnwrap(
            session.store.trackGroups.first(where: { $0.id == groupID })?.memberIDs
        )
        _ = session.createBlankGeneratorSource(trackID: memberIDs[0], slotIndex: 0)
        let generatorSlotBefore = session.store.patternBank(for: memberIDs[0]).slot(at: 0)

        session.applyPatternTemplate(template, toGroup: groupID, slotIndex: 0)

        XCTAssertEqual(
            session.store.patternBank(for: memberIDs[0]).slot(at: 0),
            generatorSlotBefore,
            "Generator-backed slots are skipped by the apply"
        )
        XCTAssertEqual(
            noteGridMainStepPattern(try XCTUnwrap(slotContent(session, trackID: memberIDs[1], slotIndex: 0))),
            template.patterns["snare"]
        )
    }

    func test_applyPatternTemplate_multiSlotIsAtomicAndLeavesActivePatternUnchanged() throws {
        let (session, box) = makeSession()
        let template = DrumKitFixtures.factoryTemplate(named: "808")
        let groupID = makeDrumGroup(in: session)
        let memberIDs = try XCTUnwrap(
            session.store.trackGroups.first(where: { $0.id == groupID })?.memberIDs
        )
        session.setDrumGroupSelectedPatternIndex(5, groupID: groupID)
        session.flushToDocumentSync()
        let documentBefore = box.document.project

        let changed = session.applyPatternTemplate(
            template,
            toGroup: groupID,
            slotIndexes: [1, 3, 3]
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(box.document.project, documentBefore)
        XCTAssertEqual(
            memberIDs.map { session.store.selectedPatternIndex(for: $0) },
            Array(repeating: 5, count: memberIDs.count)
        )

        for slotIndex in [1, 3] {
            for (memberID, tag) in zip(memberIDs, ["kick", "snare", "hat-closed"]) {
                XCTAssertEqual(
                    noteGridMainStepPattern(
                        try XCTUnwrap(slotContent(session, trackID: memberID, slotIndex: slotIndex))
                    ),
                    template.patterns[tag]
                )
            }
        }

        session.flushToDocumentSync()
        XCTAssertEqual(
            memberIDs.map { box.document.project.selectedPatternIndex(for: $0) },
            Array(repeating: 5, count: memberIDs.count)
        )
    }

    // MARK: - Explicit pattern linking (AC17, AC19, AC20)

    func test_newDrumGroup_defaultsLinked() throws {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        // Patterns are global, so the matrix model no longer carries a per-kit
        // link flag; the group-level intent still defaults to linked.
        XCTAssertEqual(
            session.store.trackGroups.first(where: { $0.id == groupID })?.isPatternLinked,
            true
        )
    }

    func test_linking_doesNotGangMute() throws {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let memberIDs = try XCTUnwrap(
            session.store.trackGroups.first(where: { $0.id == groupID })?.memberIDs
        )

        // Mute one part while linked, then gang the slot. Mute stays per-part.
        session.setTrackMuted(true, trackID: memberIDs[0])
        session.setDrumGroupSelectedPatternIndex(2, groupID: groupID)

        let exported = session.store.exportToProject()
        XCTAssertEqual(exported.tracks.first(where: { $0.id == memberIDs[0] })?.mix.isMuted, true)
        XCTAssertEqual(exported.tracks.first(where: { $0.id == memberIDs[1] })?.mix.isMuted, false)
        XCTAssertEqual(exported.tracks.first(where: { $0.id == memberIDs[2] })?.mix.isMuted, false)
        // Slots still ganged.
        for memberID in memberIDs {
            XCTAssertEqual(exported.selectedPatternIndex(for: memberID), 2)
        }
    }

    func test_editingStepContent_doesNotBreakLink() throws {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let model = try XCTUnwrap(matrixModel(session, groupID: groupID))
        let row = try XCTUnwrap(model.rows.first)
        XCTAssertNotNil(model.groupSelectedSlotIndex)

        // Edit one part's step content in the shared slot (AC19).
        guard case let .editable(_, lengthSteps, steps) = row.content else {
            return XCTFail("expected editable row")
        }
        let edit = try XCTUnwrap(
            DrumKitMatrixStepEdit.tappedContent(
                layer: .steps,
                lane: .main,
                stepIndex: 5,
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: row.defaultNote
            )
        )
        commitMatrixEdit(session, row: row, content: edit)

        let after = try XCTUnwrap(matrixModel(session, groupID: groupID))
        XCTAssertNotNil(after.groupSelectedSlotIndex, "All parts still share the slot")
    }

    private static func captureContent(memberOffset: Int) -> ClipContent {
        var steps = Array(repeating: ClipStep.empty, count: 16)
        steps[memberOffset] = ClipStep(
            main: ClipLane(
                chance: 1,
                notes: [
                    ClipStepNote(
                        pitch: 60 + memberOffset,
                        velocity: 100,
                        lengthSteps: 1
                    ),
                ]
            ),
            fill: nil
        )
        return .noteGrid(lengthSteps: 16, steps: steps)
    }

}
