import SwiftUI
import XCTest
@testable import SequencerAI

/// Integration tests for the CR2-1 and CR2-2 fixes:
///
/// CR2-1: `session.setEditedDestination` must route through
///        `Project.setDestinationWithMacros` so that `syncBuiltinMacros` fires
///        in production, not only when tests call `setDestinationWithMacros` directly.
///
/// CR2-2: `syncBuiltinMacros` must use `removeMacro(id:from:)` for each dropped
///        binding so that phrase layers and clip macro lanes are cascade-purged.
@MainActor
final class SessionDestinationMacroTests: XCTestCase {

    // MARK: - Helpers

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

    private func makeAUComponentID() -> AudioComponentID {
        AudioComponentID(type: "aumu", subtype: "test", manufacturer: "test", version: 1)
    }

    // MARK: - CR2-1: session.setEditedDestination triggers syncBuiltinMacros

    /// Switch a track from AU to sampler via `session.setEditedDestination` and
    /// assert the eight sampler built-ins appear in the live store.
    func test_setEditedDestination_auToSampler_installsBuiltinMacros() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, _) = makeSession(project: project)

        let sampleID = UUID()
        session.setEditedDestination(.sample(sampleID: sampleID, settings: .default), for: trackID)

        let liveProject = session.store.exportToProject()
        let track = try XCTUnwrap(liveProject.tracks.first(where: { $0.id == trackID }))

        XCTAssertEqual(track.macros.count, 8,
            "session.setEditedDestination to sampler must install all 8 built-in macros")

        let kinds = Set(track.macros.compactMap { binding -> BuiltinMacroKind? in
            if case let .builtin(k) = binding.source { return k }
            return nil
        })
        XCTAssertEqual(kinds, Set(BuiltinMacroKind.allCases),
            "All BuiltinMacroKind cases must be present after AU-to-sampler transition")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    /// Switch a track from sampler to AU via `session.setEditedDestination` and
    /// assert the built-in macros are removed from the live store.
    func test_setEditedDestination_samplerToAU_removesBuiltinMacros() throws {
        // Start with a sampler destination so built-ins are installed.
        let sampleID = UUID()
        let (baseProject, trackID, _) = makeLiveStoreProject()
        var project = baseProject
        project.setDestinationWithMacros(.sample(sampleID: sampleID, settings: .default), for: trackID)
        project.syncMacroLayers()

        XCTAssertEqual(
            project.tracks.first(where: { $0.id == trackID })?.macros.count, 8,
            "Precondition: sampler track must have 8 built-in macros"
        )

        let (session, _) = makeSession(project: project)

        // Switch to AU via the session API (the path that was broken in CR2-1).
        session.setEditedDestination(
            .auInstrument(componentID: makeAUComponentID(), stateBlob: nil),
            for: trackID
        )

        let liveProject = session.store.exportToProject()
        let track = try XCTUnwrap(liveProject.tracks.first(where: { $0.id == trackID }))

        XCTAssertTrue(track.macros.isEmpty,
            "session.setEditedDestination to AU must remove sampler built-in macros")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - CR2-2: syncBuiltinMacros cascades through removeMacro

    /// Start with an AU track that has two AU macro bindings, each with a
    /// per-step macroLane entry on a clip. Switch to sampler via
    /// `session.setEditedDestination`. Assert:
    ///   - AU bindings are gone from track.macros
    ///   - The two macro layer entries are gone from project.layers
    ///   - The clip's macroLanes entries for both bindings are gone
    func test_setEditedDestination_auToSampler_cascadesPurgesLayersAndClipLanes() throws {
        let bindingAID = UUID()
        let bindingBID = UUID()

        let descriptorA = TrackMacroDescriptor(
            id: bindingAID, displayName: "ParamA",
            minValue: 0, maxValue: 1, defaultValue: 0,
            valueType: .scalar, source: .auParameter(address: 10, identifier: "a")
        )
        let descriptorB = TrackMacroDescriptor(
            id: bindingBID, displayName: "ParamB",
            minValue: 0, maxValue: 1, defaultValue: 0,
            valueType: .scalar, source: .auParameter(address: 20, identifier: "b")
        )

        var (project, trackID, clipID) = makeLiveStoreProject()

        // Give the track an AU destination and two AU macro bindings.
        project.setDestinationWithMacros(
            .auInstrument(componentID: makeAUComponentID(), stateBlob: nil),
            for: trackID
        )
        project.addAUMacro(descriptor: descriptorA, to: trackID)
        project.addAUMacro(descriptor: descriptorB, to: trackID)
        project.syncMacroLayers()

        // Write per-step macro lane entries on the clip.
        if let clipIndex = project.clipPool.firstIndex(where: { $0.id == clipID }) {
            project.clipPool[clipIndex].macroLanes[bindingAID] = MacroLane(values: [0.3, nil])
            project.clipPool[clipIndex].macroLanes[bindingBID] = MacroLane(values: [0.7, nil])
        }

        let layerAID = "macro-\(trackID.uuidString)-\(bindingAID.uuidString)"
        let layerBID = "macro-\(trackID.uuidString)-\(bindingBID.uuidString)"

        // Verify preconditions.
        XCTAssertTrue(project.layers.contains(where: { $0.id == layerAID }),
            "Precondition: layer A must exist before transition")
        XCTAssertTrue(project.layers.contains(where: { $0.id == layerBID }),
            "Precondition: layer B must exist before transition")
        XCTAssertNotNil(project.clipPool.first(where: { $0.id == clipID })?.macroLanes[bindingAID],
            "Precondition: clipPool must have macro lane A")
        XCTAssertNotNil(project.clipPool.first(where: { $0.id == clipID })?.macroLanes[bindingBID],
            "Precondition: clipPool must have macro lane B")

        let (session, _) = makeSession(project: project)

        // Switch to sampler via session.setEditedDestination (the CR2-1 seam).
        session.setEditedDestination(.sample(sampleID: UUID(), settings: .default), for: trackID)

        let liveProject = session.store.exportToProject()
        let track = try XCTUnwrap(liveProject.tracks.first(where: { $0.id == trackID }))
        let liveClip = try XCTUnwrap(liveProject.clipPool.first(where: { $0.id == clipID }))

        // AU bindings must be gone; only the 8 sampler built-ins remain.
        XCTAssertFalse(track.macros.contains { $0.id == bindingAID },
            "AU binding A must be removed from track.macros after sampler transition")
        XCTAssertFalse(track.macros.contains { $0.id == bindingBID },
            "AU binding B must be removed from track.macros after sampler transition")
        XCTAssertEqual(track.macros.count, 8,
            "Only the 8 sampler built-ins must remain after AU-to-sampler transition")

        // Macro layer entries must be gone.
        XCTAssertFalse(liveProject.layers.contains(where: { $0.id == layerAID }),
            "Phrase layer for binding A must be removed on sampler transition (CR2-2 cascade)")
        XCTAssertFalse(liveProject.layers.contains(where: { $0.id == layerBID }),
            "Phrase layer for binding B must be removed on sampler transition (CR2-2 cascade)")

        // Clip macro lanes must be gone.
        XCTAssertNil(liveClip.macroLanes[bindingAID],
            "Clip macro lane for binding A must be removed on sampler transition (CR2-2 cascade)")
        XCTAssertNil(liveClip.macroLanes[bindingBID],
            "Clip macro lane for binding B must be removed on sampler transition (CR2-2 cascade)")

        SequencerDocumentSessionRegistry.unregister(session)
    }
}
