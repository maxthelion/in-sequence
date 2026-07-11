import SwiftUI
import XCTest
@testable import SequencerAI

private final class SceneDocumentEditDocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}

@MainActor
final class DocumentEditCommandControllerTests: XCTestCase {
    private let stepsDomain: DocumentEditCommandController.Domain = "steps"
    private let tracksDomain: DocumentEditCommandController.Domain = "tracks"

    func testAvailabilityReflectsActiveTargetImmediately() {
        let controller = DocumentEditCommandController()
        var hasSelection = false

        XCTAssertEqual(controller.availability, .unavailable)

        controller.register(target: makeTarget(
            canCopy: { hasSelection },
            canClear: { hasSelection }
        ))

        XCTAssertEqual(
            controller.availability,
            .init(canCopy: false, canPaste: false, canClear: false)
        )

        hasSelection = true

        XCTAssertEqual(
            controller.availability,
            .init(canCopy: true, canPaste: false, canClear: true)
        )
    }

    func testCompatiblePayloadEnablesAndExecutesPaste() throws {
        let controller = DocumentEditCommandController()
        var pastedSteps: [Int]?

        controller.register(target: makeTarget(
            copy: { [stepsDomain] in
                .init(domain: stepsDomain, snapshot: [1, 3, 5])
            }
        ))
        XCTAssertTrue(controller.copy())

        controller.register(target: makeTarget(
            compatibleDomain: stepsDomain,
            paste: { payload in
                pastedSteps = payload.value(as: [Int].self)
            }
        ))

        XCTAssertTrue(controller.availability.canPaste)
        XCTAssertTrue(controller.paste())
        XCTAssertEqual(pastedSteps, [1, 3, 5])
        XCTAssertEqual(controller.clipboardPayload?.domain, stepsDomain)
    }

    func testIncompatiblePayloadDisablesAndDoesNotExecutePaste() {
        let controller = DocumentEditCommandController()
        var pasteCount = 0

        controller.register(target: makeTarget(
            copy: { [stepsDomain] in
                .init(domain: stepsDomain, snapshot: [1, 2])
            }
        ))
        XCTAssertTrue(controller.copy())

        controller.register(target: makeTarget(
            compatibleDomain: tracksDomain,
            paste: { _ in pasteCount += 1 }
        ))

        XCTAssertFalse(controller.availability.canPaste)
        XCTAssertFalse(controller.paste())
        XCTAssertEqual(pasteCount, 0)
    }

    func testReplacementRoutesCommandsOnlyToNewestTarget() {
        let controller = DocumentEditCommandController()
        var firstCopyCount = 0
        var secondCopyCount = 0

        controller.register(target: makeTarget(copy: { [stepsDomain] in
            firstCopyCount += 1
            return .init(domain: stepsDomain, snapshot: "first")
        }))
        controller.register(target: makeTarget(copy: { [tracksDomain] in
            secondCopyCount += 1
            return .init(domain: tracksDomain, snapshot: "second")
        }))

        XCTAssertTrue(controller.copy())
        XCTAssertEqual(firstCopyCount, 0)
        XCTAssertEqual(secondCopyCount, 1)
        XCTAssertEqual(controller.clipboardPayload?.domain, tracksDomain)
    }

    func testParentOwnerCanUpdateWithoutReplacingActiveChild() {
        let controller = DocumentEditCommandController()
        let staleToken = controller.register(target: makeTarget(canCopy: { false }))
        let currentToken = controller.register(target: makeTarget(canCopy: { true }))

        XCTAssertTrue(controller.update(
            target: makeTarget(canCopy: { true }, canClear: { true }),
            ownership: staleToken
        ))
        XCTAssertFalse(controller.unregister(ownership: staleToken))
        XCTAssertTrue(controller.availability.canCopy)
        XCTAssertFalse(controller.availability.canClear)

        XCTAssertTrue(controller.unregister(ownership: currentToken))
        XCTAssertEqual(controller.availability, .unavailable)
    }

    func testUnregisteringNestedTargetRestoresParentTarget() {
        let controller = DocumentEditCommandController()
        let parent = controller.register(target: makeTarget(canCopy: { true }))
        let child = controller.register(target: makeTarget(canCopy: { false }, canClear: { true }))

        XCTAssertEqual(
            controller.availability,
            .init(canCopy: false, canPaste: false, canClear: true)
        )
        XCTAssertTrue(controller.unregister(ownership: child))
        XCTAssertEqual(
            controller.availability,
            .init(canCopy: true, canPaste: false, canClear: false)
        )
        XCTAssertTrue(controller.unregister(ownership: parent))
        XCTAssertEqual(controller.availability, .unavailable)
    }

    func testCopyPasteAndClearExecuteTheirSuppliedClosures() {
        let controller = DocumentEditCommandController()
        var hasSelection = true
        var copiedValue = 0
        var pastedValue: Int?
        var clearCount = 0

        controller.register(target: makeTarget(
            canCopy: { hasSelection },
            canClear: { hasSelection },
            compatibleDomain: stepsDomain,
            copy: { [stepsDomain] in
                copiedValue += 1
                return .init(domain: stepsDomain, snapshot: 42)
            },
            paste: { payload in
                pastedValue = payload.value(as: Int.self)
            },
            clearSelection: {
                clearCount += 1
                hasSelection = false
            }
        ))

        XCTAssertTrue(controller.copy())
        XCTAssertTrue(controller.paste())
        XCTAssertTrue(controller.clearSelection())
        XCTAssertEqual(copiedValue, 1)
        XCTAssertEqual(pastedValue, 42)
        XCTAssertEqual(clearCount, 1)
        XCTAssertFalse(controller.availability.canCopy)
        XCTAssertFalse(controller.availability.canClear)
    }

    func testSceneTargetCopiesDetachedSnapshotAndPastesIndependentScene() throws {
        let fixture = makeSession()
        defer { SequencerDocumentSessionRegistry.unregister(fixture.session) }
        let controller = fixture.session.documentEditCommands
        let sourceID = fixture.session.store.masterBus.activeSceneID
        fixture.session.setMasterSceneName(sourceID, name: "Copied Before Edit")
        let sourceInsert = MasterBusInsert.filter()
        fixture.session.addMasterBusInsert(sourceInsert, to: sourceID)
        fixture.session.upsertMasterSceneMacroBinding(
            MasterSceneMacroBinding(slotIndex: 0, target: .filterCutoff(insertID: sourceInsert.id)),
            in: sourceID
        )
        var pastedID: UUID?

        controller.register(target: SceneDocumentEditCommandTarget(
            session: fixture.session,
            sceneID: sourceID,
            didPaste: { pastedID = $0 },
            clearSelection: {}
        ).target)

        XCTAssertTrue(controller.copy())
        fixture.session.setMasterSceneName(sourceID, name: "Edited After Copy")
        XCTAssertTrue(controller.paste())

        let pasted = try XCTUnwrap(pastedID.flatMap { fixture.session.store.masterBus.scene(id: $0) })
        let pastedInsert = try XCTUnwrap(pasted.inserts.first)
        XCTAssertEqual(pasted.name, "Copied Before Edit Copy")
        XCTAssertNotEqual(pasted.id, sourceID)
        XCTAssertNotEqual(pastedInsert.id, sourceInsert.id)
        guard case let .filterCutoff(targetInsertID) = try XCTUnwrap(pasted.macroBindings.first).target else {
            return XCTFail("Expected a filterCutoff macro target")
        }
        XCTAssertEqual(targetInsertID, pastedInsert.id)
    }

    func testSceneTargetRequiresSelectionAndClearOnlyRunsSelectionCallback() {
        let fixture = makeSession()
        defer { SequencerDocumentSessionRegistry.unregister(fixture.session) }
        let controller = fixture.session.documentEditCommands
        let sourceID = fixture.session.store.masterBus.activeSceneID
        var didClear = false

        controller.register(target: SceneDocumentEditCommandTarget(
            session: fixture.session,
            sceneID: sourceID,
            didPaste: { _ in },
            clearSelection: { didClear = true }
        ).target)
        XCTAssertTrue(controller.copy())

        let scenesBeforeClear = fixture.session.store.masterBus.scenes
        XCTAssertTrue(controller.clearSelection())
        XCTAssertTrue(didClear)
        XCTAssertEqual(fixture.session.store.masterBus.scenes, scenesBeforeClear)

        controller.register(target: SceneDocumentEditCommandTarget(
            session: fixture.session,
            sceneID: nil,
            didPaste: { _ in XCTFail("Paste must require a selected scene target") },
            clearSelection: {}
        ).target)
        XCTAssertEqual(controller.availability, .unavailable)
        XCTAssertFalse(controller.paste())
    }

    private func makeSession() -> (session: SequencerDocumentSession, documentBox: SceneDocumentEditDocumentBox) {
        let documentBox = SceneDocumentEditDocumentBox(document: SeqAIDocument(project: .empty))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )
        return (session, documentBox)
    }

    func testTracksClipboardResolvesDetachedIDsAgainstLiveTracks() {
        let liveID = UUID()
        let deletedID = UUID()
        let clipboard = TracksDocumentEditClipboard(trackIDs: [liveID, deletedID])

        XCTAssertEqual(clipboard.resolvedTrackIDs(in: [liveID]), [liveID])
        XCTAssertTrue(clipboard.resolvedTrackIDs(in: []).isEmpty)
    }

    func testPhraseCellClipboardPasteCompatibilityRequiresMatchingLayer() {
        let controller = DocumentEditCommandController()
        let clipboard = PhraseCellDocumentEditClipboard(
            layerID: "pattern",
            cell: .steps([.index(1), .index(2)])
        )
        controller.register(target: makeTarget(copy: {
            .init(domain: .phraseCells, snapshot: clipboard)
        }))
        XCTAssertTrue(controller.copy())

        controller.register(target: .init(
            canCopy: { false },
            canClear: { false },
            isPasteCompatible: { payload in
                payload.value(as: PhraseCellDocumentEditClipboard.self)?
                    .isCompatible(with: "mute") == true
            },
            copy: { nil },
            paste: { _ in },
            clearSelection: {}
        ))
        XCTAssertFalse(controller.availability.canPaste)

        controller.register(target: .init(
            canCopy: { false },
            canClear: { false },
            isPasteCompatible: { payload in
                payload.value(as: PhraseCellDocumentEditClipboard.self)?
                    .isCompatible(with: "pattern") == true
            },
            copy: { nil },
            paste: { _ in },
            clearSelection: {}
        ))
        XCTAssertTrue(controller.availability.canPaste)
    }

    func testPhraseCellClipboardCopiesAuthoredAutomationWithoutFlattening() throws {
        var track = StepSequenceTrack.default
        let group = TrackGroup(name: "Kit", color: "#12AB34", memberIDs: [track.id])
        track.groupID = group.id
        let layer = try XCTUnwrap(PhraseLayerDefinition.defaultSet(for: [track]).first { $0.id == "pattern" })
        var phrase = PhraseModel.default(
            tracks: [track],
            layers: [layer],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        let automated: PhraseCell = .bars([.index(1), .index(4), .index(2)])
        phrase.setCell(automated, for: layer.id, trackID: track.id)

        let clipboard = PhraseCellDocumentEditClipboard.copying(
            phrase: phrase,
            layer: layer,
            track: track,
            groups: [group]
        )

        XCTAssertEqual(clipboard.cell, automated)
        XCTAssertEqual(clipboard.sourceTrackName, track.name)
        XCTAssertEqual(clipboard.sourceAccentHex, group.color)
        XCTAssertEqual(clipboard.layerID, layer.id)
    }

    func testPhrasePerformPaletteRoundTripPastesOnlyPayloadIntoTargetAddress() throws {
        var tracks = [StepSequenceTrack.default]
        var targetTrack = StepSequenceTrack.default
        targetTrack.id = UUID()
        targetTrack.name = "Target"
        tracks.append(targetTrack)
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let pattern = try XCTUnwrap(layers.first { $0.id == "pattern" })
        let mute = try XCTUnwrap(layers.first { $0.id == "mute" })
        var phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        let automated: PhraseCell = .bars([.index(1), .index(4), .index(2)])
        phrase.setCell(automated, for: pattern.id, trackID: tracks[0].id)
        let source = PhraseCellDocumentEditClipboard.copying(
            phrase: phrase,
            layer: pattern,
            track: tracks[0]
        )
        let paletteEntry = PhrasePerformPaletteEntry(clipboard: source)
        let pasted = paletteEntry.documentEditClipboard

        guard case let .authored(cell) = pasted.payload else {
            return XCTFail("Expected authored phrase-cell payload")
        }
        phrase.setCell(cell, for: pattern.id, trackID: tracks[1].id)

        XCTAssertEqual(phrase.cell(for: pattern.id, trackID: tracks[1].id), automated)
        XCTAssertEqual(phrase.cell(for: mute.id, trackID: tracks[1].id), .inheritDefault)
        XCTAssertEqual(pasted.layerID, pattern.id)
        XCTAssertEqual(paletteEntry.sourceTrackName, tracks[0].name)
    }

    func testNoteRepeatPalettePayloadDoesNotCarryTrackIdentity() {
        let clipboard = PhraseCellDocumentEditClipboard(
            layerID: "runtime-note-repeat",
            payload: .noteRepeat(interval: .oneThirtySecond, isActive: true),
            sourceTrackName: "Kick",
            sourceAccentHex: "#FF6600",
            layerName: "Note Repeat"
        )

        let decoded = PhrasePerformPaletteEntry(clipboard: clipboard).documentEditClipboard

        XCTAssertEqual(decoded.payload, .noteRepeat(interval: .oneThirtySecond, isActive: true))
        XCTAssertEqual(decoded.layerID, "runtime-note-repeat")
    }

    func testPhraseCellSelectionLifecycleScopesAdditiveSelectionAndClear() {
        let phraseID = UUID()
        let otherPhraseID = UUID()
        let firstTrackID = UUID()
        let secondTrackID = UUID()
        var selection = PhraseCellDocumentSelection()

        selection.select(
            phraseID: phraseID,
            layerID: "pattern",
            trackID: firstTrackID,
            additive: false
        )
        selection.select(
            phraseID: phraseID,
            layerID: "pattern",
            trackID: secondTrackID,
            additive: true
        )
        XCTAssertEqual(
            selection.matchingTrackIDs(
                phraseID: phraseID,
                layerID: "pattern",
                liveTrackIDs: [firstTrackID, secondTrackID]
            ),
            [firstTrackID, secondTrackID]
        )

        selection.select(
            phraseID: phraseID,
            layerID: "mute",
            trackID: secondTrackID,
            additive: true
        )
        XCTAssertEqual(selection.count, 1, "Changing layer starts a new cell selection")
        selection.reconcile(
            phraseID: otherPhraseID,
            layerID: "mute",
            liveTrackIDs: [secondTrackID]
        )
        XCTAssertTrue(selection.isEmpty, "Changing phrase clears transient cell selection")

        selection.select(
            phraseID: phraseID,
            layerID: "pattern",
            trackID: firstTrackID,
            additive: false
        )
        selection.reconcile(
            phraseID: phraseID,
            layerID: "pattern",
            liveTrackIDs: []
        )
        XCTAssertTrue(selection.isEmpty, "Removing selected tracks clears the selection")

        selection.select(
            phraseID: phraseID,
            layerID: "pattern",
            trackID: firstTrackID,
            additive: false
        )
        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    func testPhraseCellSelectionToggleContractAppliesToEveryLayerType() {
        let phraseID = UUID()
        let firstTrackID = UUID()
        let secondTrackID = UUID()

        for layerID in ["mute", "pattern", "velocity"] {
            var selection = PhraseCellDocumentSelection()

            selection.applySelectionGesture(
                .singleSelection,
                phraseID: phraseID,
                layerID: layerID,
                trackID: firstTrackID
            )
            XCTAssertTrue(selection.contains(firstTrackID), "Secondary click should start a one-cell \(layerID) selection")

            selection.applySelectionGesture(
                .singleSelection,
                phraseID: phraseID,
                layerID: layerID,
                trackID: firstTrackID
            )
            XCTAssertTrue(selection.isEmpty, "Secondary click should toggle off a sole \(layerID) selection")

            selection.applySelectionGesture(
                .singleSelection,
                phraseID: phraseID,
                layerID: layerID,
                trackID: firstTrackID
            )
            selection.applySelectionGesture(
                .additiveToggle,
                phraseID: phraseID,
                layerID: layerID,
                trackID: secondTrackID
            )
            XCTAssertEqual(selection.count, 2, "Shift-click should additively toggle \(layerID) cells on")

            selection.applySelectionGesture(
                .additiveToggle,
                phraseID: phraseID,
                layerID: layerID,
                trackID: firstTrackID
            )
            XCTAssertFalse(selection.contains(firstTrackID), "Shift-click should additively toggle \(layerID) cells off")
            XCTAssertTrue(selection.contains(secondTrackID))

            selection.applySelectionGesture(
                .singleSelection,
                phraseID: phraseID,
                layerID: layerID,
                trackID: firstTrackID
            )
            XCTAssertTrue(selection.contains(firstTrackID), "Secondary click should replace a \(layerID) selection")
            XCTAssertFalse(selection.contains(secondTrackID))

            selection.applySelectionGesture(
                .additiveToggle,
                phraseID: phraseID,
                layerID: layerID,
                trackID: firstTrackID
            )
            XCTAssertTrue(selection.isEmpty)
            XCTAssertNil(selection.phraseID)
            XCTAssertNil(selection.layerID)
        }
    }

    private func makeTarget(
        canCopy: @escaping () -> Bool = { true },
        canClear: @escaping () -> Bool = { false },
        compatibleDomain: DocumentEditCommandController.Domain? = nil,
        copy: @escaping () -> DocumentEditCommandController.ClipboardPayload? = { nil },
        paste: @escaping (DocumentEditCommandController.ClipboardPayload) -> Void = { _ in },
        clearSelection: @escaping () -> Void = {}
    ) -> DocumentEditCommandController.Target {
        .init(
            canCopy: canCopy,
            canClear: canClear,
            isPasteCompatible: { payload in payload.domain == compatibleDomain },
            copy: copy,
            paste: paste,
            clearSelection: clearSelection
        )
    }
}
