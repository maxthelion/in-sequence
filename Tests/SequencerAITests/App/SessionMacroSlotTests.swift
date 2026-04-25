import SwiftUI
import XCTest
@testable import SequencerAI

/// Regression tests for the typed macro slot session API.
///
/// - C4: `removeAUMacroSlot` must cascade into `clipPool` (macro lanes purged).
/// - I9: After slot removal, `compileClipBuffer` must not include the dropped
///   binding ID in `macroBindingOrder`.
@MainActor
final class SessionMacroSlotTests: XCTestCase {

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) { self.document = document }
    }

    private func makeSession(project: Project) -> (SequencerDocumentSession, DocumentBox) {
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )
        return (session, box)
    }

    // MARK: - C4: removeMacroSlot purges clip macro lane

    /// Bind a macro slot, set a per-step lane on the clip, remove the slot via
    /// `session.removeAUMacroSlot`, reload from store, assert the orphan lane is gone.
    func test_removeAUMacroSlot_purgesClipMacroLane() throws {
        var (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60)

        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Gain",
            minValue: -60, maxValue: 12, defaultValue: 0,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "gain")
        )
        let bindingID = descriptor.id

        // Bind the macro.
        project.addAUMacro(descriptor: descriptor, to: trackID)
        project.syncMacroLayers()

        // Write a per-step lane on the clip.
        if let clipIndex = project.clipPool.firstIndex(where: { $0.id == clipID }) {
            project.clipPool[clipIndex].macroLanes[bindingID] = MacroLane(values: [0.5, nil])
        }
        XCTAssertNotNil(
            project.clipPool.first(where: { $0.id == clipID })?.macroLanes[bindingID],
            "Precondition: clip must have a macro lane before removal"
        )

        let (session, _) = makeSession(project: project)

        // Remove the slot via the typed session method.
        session.removeAUMacroSlot(bindingID: bindingID, trackID: trackID)

        // The clip pool in the live store must no longer carry the orphan lane.
        let liveClip = try XCTUnwrap(
            session.store.exportToProject().clipPool.first(where: { $0.id == clipID }),
            "Clip must still exist in the pool"
        )
        XCTAssertNil(
            liveClip.macroLanes[bindingID],
            "Orphan macro lane must be removed from clipPool after removeAUMacroSlot"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - I9: compiler does not emit dropped binding in macroBindingOrder

    /// After a slot is removed via `session.removeAUMacroSlot`, recompile the
    /// snapshot and assert the dropped binding ID does not appear in
    /// `macroBindingOrder` for the affected clip.
    func test_compileClipBuffer_excludesRemovedBinding_afterSlotRemoval() throws {
        var (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60)

        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Res",
            minValue: 0, maxValue: 1, defaultValue: 0,
            valueType: .scalar,
            source: .auParameter(address: 2, identifier: "res")
        )
        let bindingID = descriptor.id

        project.addAUMacro(descriptor: descriptor, to: trackID)
        project.syncMacroLayers()

        if let clipIndex = project.clipPool.firstIndex(where: { $0.id == clipID }) {
            project.clipPool[clipIndex].macroLanes[bindingID] = MacroLane(values: [0.3, nil])
        }

        let (session, _) = makeSession(project: project)

        // Verify binding appears in snapshot before removal.
        let snapshotBefore = SequencerSnapshotCompiler.compile(state: session.store.compileInput())
        let bufferBefore = snapshotBefore.clipBuffersByID[clipID]
        XCTAssertTrue(
            bufferBefore?.macroBindingOrder.contains(bindingID) == true,
            "Precondition: bindingID must appear in macroBindingOrder before removal"
        )

        // Remove the slot.
        session.removeAUMacroSlot(bindingID: bindingID, trackID: trackID)

        // Recompile and verify binding is gone.
        let snapshotAfter = SequencerSnapshotCompiler.compile(state: session.store.compileInput())
        let bufferAfter = snapshotAfter.clipBuffersByID[clipID]
        XCTAssertFalse(
            bufferAfter?.macroBindingOrder.contains(bindingID) == true,
            "Dropped binding must not appear in macroBindingOrder after removeAUMacroSlot"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - assignAUMacroToSlot cascade

    /// `assignAUMacroToSlot` must write the new binding into the live store
    /// (track macros + layers), visible without a flush.
    func test_assignAUMacroToSlot_writesBindingIntoStore() throws {
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)
        let (session, _) = makeSession(project: project)

        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff",
            minValue: 0, maxValue: 1, defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 10, identifier: "cutoff")
        )

        session.assignAUMacroToSlot(descriptor, to: trackID, slotIndex: 3)

        let liveProject = session.store.exportToProject()
        let track = try XCTUnwrap(liveProject.tracks.first(where: { $0.id == trackID }))
        XCTAssertTrue(
            track.macros.contains { $0.id == descriptor.id && $0.slotIndex == 3 },
            "New AU macro must appear at slot 3 in the live store after assignAUMacroToSlot"
        )

        // A macro layer must have been created.
        let layerID = "macro-\(trackID.uuidString)-\(descriptor.id.uuidString)"
        XCTAssertTrue(
            liveProject.layers.contains { $0.id == layerID },
            "A phrase layer must be created for the new macro binding"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }
}
