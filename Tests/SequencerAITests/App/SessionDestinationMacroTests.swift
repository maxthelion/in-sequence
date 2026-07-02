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

    private func makeSessionWithEngine(project: Project) -> (SequencerDocumentSession, EngineController, DocumentBox) {
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine
        )
        return (session, engine, box)
    }

    private func makeAUComponentID() -> AudioComponentID {
        AudioComponentID(type: "aumu", subtype: "test", manufacturer: "test", version: 1)
    }

    /// A temp on-disk sample library so `addDrumGroup(plan:.blankDefault)` seeds
    /// each member with a real `.sample` destination (mirrors ProjectAddDrumGroupTests).
    private func makeTempLibrary() throws -> AudioSampleLibrary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in ["kick", "snare", "hatClosed", "clap"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("\(name)-default.wav"))
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AudioSampleLibrary(libraryRoot: root)
    }

    // MARK: - Step 1 (X-click bug): clearing a kit member's sound

    /// The drum-kit Sound tab's X button must clear the member part's sound by
    /// calling `session.setEditedDestination(.none, for: memberID)`. This proves
    /// the clear lands in the live document store (the normal undoable edit path),
    /// NOT as a transient empty written somewhere else.
    func test_setEditedDestination_none_clearsKitMemberSound() throws {
        let library = try makeTempLibrary()
        var project = Project.empty
        guard let groupID = project.addDrumGroup(plan: .blankDefault, library: library),
              let memberID = project.trackGroups.first(where: { $0.id == groupID })?.memberIDs.first
        else {
            return XCTFail("expected a populated drum group with at least one member")
        }

        // Precondition: the member starts with a real (sample) sound, not .none.
        XCTAssertEqual(
            project.tracks.first(where: { $0.id == memberID })?.destination.kind, .sample,
            "Precondition: blankDefault member should start with a sample destination"
        )

        let (session, _) = makeSession(project: project)

        // The X-click wiring under test.
        session.setEditedDestination(.none, for: memberID)

        let liveProject = session.store.exportToProject()
        let member = try XCTUnwrap(liveProject.tracks.first(where: { $0.id == memberID }))

        XCTAssertEqual(member.destination, .none,
            "Clicking the Sound tab X must clear the member's destination to .none")

        // The cleared member must still be a member of its group (clearing the
        // sound does not remove the part) — document/runtime stay consistent.
        let group = try XCTUnwrap(liveProject.trackGroups.first(where: { $0.id == groupID }))
        XCTAssertTrue(group.memberIDs.contains(memberID),
            "Clearing the sound must not remove the part from the kit group")

        SequencerDocumentSessionRegistry.unregister(session)
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

    // MARK: - Macro layer default drags (scoped runtime — no snapshot install)

    /// A macro-knob drag is dispatch-time only (sampler/filter/AU params) — it
    /// must NOT bump the generation-input revision (which would bust the
    /// precompute cache and clear the event queue at mouse-move rate, the
    /// latency class already fixed for `setTrackMix`), and the dragged value
    /// must reach the engine through the scoped-runtime override so the knob
    /// still works without a snapshot install.
    func test_setMacroLayerDefault_dragSkipsSnapshotInstall_butReachesEngine() throws {
        let library = try makeTempLibrary()
        var project = Project.empty
        guard let groupID = project.addDrumGroup(plan: .blankDefault, library: library),
              let memberID = project.trackGroups.first(where: { $0.id == groupID })?.memberIDs.first
        else {
            return XCTFail("expected a populated drum group with at least one member")
        }

        let (session, engine, _) = makeSessionWithEngine(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let liveProject = session.store.exportToProject()
        guard let binding = liveProject.tracks.first(where: { $0.id == memberID })?.macros.first else {
            return XCTFail("expected the sample member to carry builtin macro bindings")
        }

        let revisionBefore = engine.tickState.readPrepareInputs().generationInputRevision
        let storeRevisionBefore = session.store.revision

        session.setMacroLayerDefault(value: 0.42, bindingID: binding.id, trackID: memberID)

        XCTAssertEqual(
            engine.tickState.readPrepareInputs().generationInputRevision, revisionBefore,
            "a macro-default drag must not install a snapshot / bump the generation revision"
        )
        XCTAssertEqual(
            engine.macroLayerDefaultOverridesForTesting[memberID]?[binding.id], 0.42,
            "the dragged value must reach the engine via the scoped-runtime override (knob must still work)"
        )
        XCTAssertGreaterThan(
            session.store.revision, storeRevisionBefore,
            "the drag must still persist into the store for flush/undo/export and the next compile"
        )
    }

    /// The engine-side override is a bridge until the next real snapshot
    /// install; the install compiles the store value the drag already wrote,
    /// so the override must clear there (no stale per-drag values leaking
    /// across snapshot generations).
    func test_macroDefaultOverride_clearsOnSnapshotInstall() throws {
        let library = try makeTempLibrary()
        var project = Project.empty
        guard let groupID = project.addDrumGroup(plan: .blankDefault, library: library),
              let memberID = project.trackGroups.first(where: { $0.id == groupID })?.memberIDs.first
        else {
            return XCTFail("expected a populated drum group with at least one member")
        }

        let (session, engine, _) = makeSessionWithEngine(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        guard let binding = session.store.exportToProject()
            .tracks.first(where: { $0.id == memberID })?.macros.first
        else {
            return XCTFail("expected builtin macro bindings")
        }

        session.setMacroLayerDefault(value: 0.42, bindingID: binding.id, trackID: memberID)
        XCTAssertNotNil(engine.macroLayerDefaultOverridesForTesting[memberID]?[binding.id])

        engine.apply(documentModel: session.store.exportToProject())

        XCTAssertTrue(
            engine.macroLayerDefaultOverridesForTesting.isEmpty,
            "a snapshot install compiles the persisted default — the override must clear"
        )
    }

    /// Structural layer edits (arrangement-level phrase-layer defaults) are NOT
    /// the live-drag path and must keep installing snapshots (revision bumps).
    func test_setPhraseLayerDefault_stillInstallsSnapshot() throws {
        let library = try makeTempLibrary()
        var project = Project.empty
        guard let groupID = project.addDrumGroup(plan: .blankDefault, library: library),
              let memberID = project.trackGroups.first(where: { $0.id == groupID })?.memberIDs.first
        else {
            return XCTFail("expected a populated drum group with at least one member")
        }

        let (session, engine, _) = makeSessionWithEngine(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        guard let layer = session.store.exportToProject().layers.first else {
            return XCTFail("expected at least one layer")
        }

        let revisionBefore = engine.tickState.readPrepareInputs().generationInputRevision

        session.setPhraseLayerDefault(.scalar(0.7), layerID: layer.id, trackID: memberID)

        XCTAssertGreaterThan(
            engine.tickState.readPrepareInputs().generationInputRevision, revisionBefore,
            "structural layer edits must keep installing snapshots"
        )
    }
}
