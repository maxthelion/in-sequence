import XCTest
import SwiftUI
@testable import SequencerAI

/// Verifies the `session.batch(impact:_:)` helper:
///   - publishes exactly one snapshot regardless of how many typed store mutations run
///   - returns `false` when no state change occurs
///   - properly dispatches the chosen impact

@MainActor
final class SessionBatchHelperTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(
        project: Project? = nil
    ) -> (SequencerDocumentSession, EngineController, DocumentBox) {
        let (defaultProject, _, _) = makeLiveStoreProject()
        let p = project ?? defaultProject
        let box = DocumentBox(document: SeqAIDocument(project: p))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100) // prevent flush during tests
        )
        session.activate()
        // Test-isolation convention (bacee620): every controller a test
        // creates gets a full shutdown at teardown so no TickClock or host
        // work leaks into later suites.
        addTeardownBlock {
            engine.shutdown()
        }
        return (session, engine, box)
    }

    // MARK: - One snapshot per batch

    /// A `batch` body that runs two separate typed mutations must publish
    /// exactly one snapshot — not one per typed mutation.
    func test_batch_publishesExactlyOneSnapshot_forMultipleMutations() throws {
        let (project, trackID, clipID) = makeLiveStoreProject()
        let (session, engine, _) = makeSession(project: project)
        let snapshotsBefore = engine.applyPlaybackSnapshotCallCount

        session.batch(impact: .snapshotOnly, changed: .track(trackID).union(.clip(clipID))) { s in
            s.mutateTrack(id: trackID) { track in
                track.name = "Batch Name"
            }
            s.mutateClip(id: clipID) { clip in
                clip.name = "Batch Clip"
            }
        }

        XCTAssertEqual(
            engine.applyPlaybackSnapshotCallCount, snapshotsBefore + 1,
            "batch must publish exactly one snapshot regardless of mutation count"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Returns false when nothing changed

    func test_batch_returnsFalse_whenNoChangeOccurs() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, _, _) = makeSession(project: project)

        // Batch that applies the track's existing name (no-op).
        let existingName = session.store.tracks.first(where: { $0.id == trackID })?.name ?? "Track"
        let result = session.batch(impact: .snapshotOnly, changed: .track(trackID)) { s in
            s.mutateTrack(id: trackID) { track in
                track.name = existingName // same value — store won't bump revision
            }
        }

        XCTAssertFalse(result, "batch must return false when nothing changed")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Returns true when something changed

    func test_batch_returnsTrue_whenChangeOccurs() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, _, _) = makeSession(project: project)

        let result = session.batch(impact: .snapshotOnly, changed: .track(trackID)) { s in
            s.mutateTrack(id: trackID) { track in
                track.name = "NewName"
            }
        }

        XCTAssertTrue(result, "batch must return true when something changed")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Clip randomize bake (WS2)

    func test_bakeRandomizedSelectedClip_overwritesClipAndPersistsSettings() throws {
        let (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true, false, false, false])
        let (session, engine, _) = makeSession(project: project)
        let originalContent = try XCTUnwrap(session.store.clipEntry(id: clipID)?.content)
        let snapshotsBefore = engine.applyPlaybackSnapshotCallCount
        let settings = ClipRandomizeSettings(
            density: 1,
            scaleID: .major,
            rootPitchClass: 5,
            octaveCenter: 4,
            octaveSpan: 0,
            velocityVariance: 0,
            gateVariance: 0
        )

        let bakedClipID = session.bakeRandomizedSelectedClip(
            trackID: trackID,
            settings: settings,
            seed: 0xBEEFBEEF
        )

        let updated = try XCTUnwrap(session.store.clipEntry(id: clipID))
        XCTAssertEqual(bakedClipID, clipID)
        XCTAssertNotEqual(updated.content, originalContent)
        XCTAssertEqual(updated.randomizeSettings?.lastSeed, 0xBEEFBEEF)
        XCTAssertEqual(updated.randomizeSettings?.rootPitchClass, 5)
        XCTAssertGreaterThan(engine.applyPlaybackSnapshotCallCount, snapshotsBefore)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_bakeRandomizedSelectedClip_survivesSaveReload() throws {
        let (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true, false, false, false])
        let (session, _, box) = makeSession(project: project)
        let settings = ClipRandomizeSettings(
            density: 1,
            scaleID: .naturalMinor,
            rootPitchClass: 2,
            octaveCenter: 4,
            octaveSpan: 0,
            velocityVariance: 0,
            gateVariance: 0
        )

        _ = session.bakeRandomizedSelectedClip(
            trackID: trackID,
            settings: settings,
            seed: 0xDEC0DE
        )
        let baked = try XCTUnwrap(session.store.clipEntry(id: clipID))
        session.flushToDocumentSync()

        let encoded = try JSONEncoder().encode(box.document.project)
        let decoded = try JSONDecoder().decode(Project.self, from: encoded)
        let decodedClip = try XCTUnwrap(decoded.clipPool.first { $0.id == clipID })

        XCTAssertEqual(decodedClip.content, baked.content)
        XCTAssertEqual(decodedClip.randomizeSettings?.lastSeed, 0xDEC0DE)
        XCTAssertEqual(decodedClip.randomizeSettings?.scaleID, .naturalMinor)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_bakeRandomizedSelectedClip_isUndoableViaExternalDocumentChange() throws {
        let (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true, false, false, false])
        let (session, _, _) = makeSession(project: project)
        let before = session.store.exportToProject()
        let originalClip = try XCTUnwrap(session.store.clipEntry(id: clipID))
        let settings = ClipRandomizeSettings(
            density: 1,
            scaleID: .major,
            rootPitchClass: 9,
            octaveCenter: 4,
            octaveSpan: 0,
            velocityVariance: 0,
            gateVariance: 0
        )

        _ = session.bakeRandomizedSelectedClip(
            trackID: trackID,
            settings: settings,
            seed: 0xA11CE
        )
        XCTAssertNotEqual(session.store.clipEntry(id: clipID)?.content, originalClip.content)
        XCTAssertNotNil(session.store.clipEntry(id: clipID)?.randomizeSettings)

        session.flushToDocumentSync()
        session.ingestExternalDocumentChange(before)

        let restoredClip = try XCTUnwrap(session.store.clipEntry(id: clipID))
        XCTAssertEqual(restoredClip.content, originalClip.content)
        XCTAssertNil(restoredClip.randomizeSettings)
        XCTAssertEqual(session.store.exportToProject(), before)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_restoreClipSnapshot_revertsRandomizeBakeForSelectedSlot() throws {
        let (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true, false, false, false])
        let (session, engine, _) = makeSession(project: project)
        let originalClip = try XCTUnwrap(session.store.clipEntry(id: clipID))
        let snapshotsBefore = engine.applyPlaybackSnapshotCallCount
        let settings = ClipRandomizeSettings(
            density: 1,
            scaleID: .major,
            rootPitchClass: 9,
            octaveCenter: 4,
            octaveSpan: 0,
            velocityVariance: 0,
            gateVariance: 0
        )

        _ = session.bakeRandomizedSelectedClip(
            trackID: trackID,
            settings: settings,
            seed: 0xCA11CE1
        )
        XCTAssertNotEqual(session.store.clipEntry(id: clipID)?.content, originalClip.content)

        let restored = session.restoreClipSnapshot(
            originalClip,
            at: PatternSlotAddress(trackID: trackID, slotIndex: 0)
        )

        XCTAssertTrue(restored)
        XCTAssertEqual(session.store.clipEntry(id: clipID), originalClip)
        XCTAssertGreaterThan(engine.applyPlaybackSnapshotCallCount, snapshotsBefore)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_auditionRandomizedSelectedClip_playsOverrideWithoutMutatingClip_andClearsOnClose() throws {
        let (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true, false, false, false])
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let audioSink = CountingAudioSink()
        let engine = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        addTeardownBlock {
            engine.shutdown()
        }
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        let originalContent = try XCTUnwrap(session.store.clipEntry(id: clipID)?.content)
        let settings = ClipRandomizeSettings(
            density: 1,
            scaleID: .major,
            rootPitchClass: 7,
            octaveCenter: 4,
            octaveSpan: 0,
            velocityVariance: 0,
            gateVariance: 0
        )

        // While the sheet is open the audition override is active: the engine
        // plays the baked preview, the document clip is untouched.
        let state = try XCTUnwrap(session.auditionRandomizedSelectedClip(
            trackID: trackID,
            settings: settings,
            seed: 0xFACE
        ))
        engine.processTick(tickIndex: 0, now: 0)

        XCTAssertEqual(session.store.clipEntry(id: clipID)?.content, originalContent)
        XCTAssertNil(session.store.clipEntry(id: clipID)?.randomizeSettings)
        let playedPitches = audioSink.playedEvents.flatMap { $0 }.map { Int($0.pitch) }
        XCTAssertEqual(playedPitches, firstStepPitches(in: state.noteGrid))
        XCTAssertFalse(playedPitches.contains(60), "audition pool (G major, no C) must replace the clip note")

        // Closing the sheet clears the override: the next cycle plays the
        // original clip content again.
        session.clearRandomizeAudition(trackID: trackID)
        audioSink.resetPlayedEvents()
        engine.processTick(tickIndex: 4, now: 0.4)

        let clearedPitches = audioSink.playedEvents.flatMap { $0 }.map { Int($0.pitch) }
        XCTAssertEqual(clearedPitches, [60], "cleared audition must restore the clip's own notes")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    private func firstStepPitches(in content: ClipContent) -> [Int] {
        guard case let .noteGrid(_, steps) = content.normalized,
              let first = steps.first
        else {
            return []
        }
        return (first.main?.notes ?? []).map(\.pitch)
    }

    // MARK: - Generator kind switching (WS4 AC1: stable identity)

    func test_switchGeneratorKind_rejects_hidden_legacy_progression_kind() throws {
        var project = makeLiveStoreProject().0
        project.appendTrack(trackType: .polyMelodic)
        let trackID = project.selectedTrackID
        let generatorID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Mutable Generator",
            trackType: .polyMelodic,
            kind: .polyGenerator,
            params: .poly(
                trigger: .native(.euclidean(pulses: 3, steps: 16, offset: 1)),
                pitches: [.native(.randomInScale(root: 57, scale: .naturalMinor, spread: 12))],
                shape: NoteShape(velocity: 77, gateLength: 5, accent: false)
            )
        )
        project.generatorPool.append(generator)
        project.assignGeneratorSource(generatorID, to: trackID, slotIndex: 0)
        let beforeRef = project.patternBank(for: trackID).slot(at: 0).sourceRef

        let (session, _, box) = makeSession(project: project)

        XCTAssertFalse(session.switchGeneratorKind(id: generatorID, to: .progressionChordGenerator))
        let updated = try XCTUnwrap(session.store.generatorEntry(id: generatorID))
        XCTAssertEqual(updated.id, generatorID)
        XCTAssertEqual(updated.name, "Mutable Generator")
        XCTAssertEqual(updated.kind, .polyGenerator)
        XCTAssertEqual(updated.trackType, .polyMelodic)
        XCTAssertEqual(session.store.patternBank(for: trackID).slot(at: 0).sourceRef.generatorID, generatorID)
        XCTAssertEqual(session.store.patternBank(for: trackID).slot(at: 0).sourceRef.mode, beforeRef.mode)
        XCTAssertEqual(updated.params, generator.params)

        session.flushToDocumentSync()

        let flushed = try XCTUnwrap(box.document.project.generatorEntry(id: generatorID))
        XCTAssertEqual(flushed.kind, .polyGenerator)
        XCTAssertEqual(flushed.id, generatorID)
        XCTAssertEqual(box.document.project.patternBank(for: trackID).slot(at: 0).sourceRef.generatorID, generatorID)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_switchGeneratorKind_rejects_incompatible_kind_for_mono_generator() throws {
        var project = makeLiveStoreProject().0
        let generatorID = UUID(uuidString: "33333333-4444-5555-6666-777777777777")!
        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Mono Guarded",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .defaultMono
        )
        project.generatorPool.append(generator)

        let (session, _, _) = makeSession(project: project)

        XCTAssertFalse(session.switchGeneratorKind(id: generatorID, to: .progressionChordGenerator))
        XCTAssertFalse(session.switchGeneratorKind(id: generatorID, to: .polyGenerator))

        let updated = try XCTUnwrap(session.store.generatorEntry(id: generatorID))
        XCTAssertEqual(updated.kind, .monoGenerator)
        XCTAssertEqual(updated.trackType, .monoMelodic)
        XCTAssertEqual(updated.params, .defaultMono)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - fullEngineApply dispatches apply(documentModel:) once

    func test_batch_fullEngineApply_callsApplyDocumentModelOnce() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, engine, _) = makeSession(project: project)
        session.activate()
        let baseline = engine.applyDocumentModelCallCount

        session.batch(impact: .fullEngineApply, changed: .full) { s in
            s.mutateTrack(id: trackID) { track in
                track.name = "Engine Apply"
            }
        }

        XCTAssertEqual(
            engine.applyDocumentModelCallCount, baseline + 1,
            ".fullEngineApply batch must call apply(documentModel:) exactly once"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Session-level typed methods respect isInBatch guard

    /// When typed session methods are called inside `batch`, they should NOT
    /// publish individually — only the outer batch publishes.
    func test_typedMethods_insideBatch_doNotPublishIndividually() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, engine, _) = makeSession(project: project)
        let before = engine.applyPlaybackSnapshotCallCount

        session.batch(impact: .snapshotOnly, changed: .track(trackID)) { _ in
            // Call a typed session method inside the batch.
            // This should NOT trigger a publish on its own.
            session.store.mutateTrack(id: trackID) { track in
                track.name = "Inner"
            }
        }

        // Exactly one snapshot from the batch end.
        XCTAssertEqual(
            engine.applyPlaybackSnapshotCallCount, before + 1,
            "typed store methods inside batch must not publish individually"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_batchWithPlaybackInertChange_doesNotPublishSnapshot() throws {
        var (project, _, _) = makeLiveStoreProject()
        let firstTrackID = project.selectedTrackID
        project.appendTrack(trackType: .monoMelodic)
        project.selectedTrackID = firstTrackID
        let trackID = project.tracks[1].id
        let (session, engine, _) = makeSession(project: project)
        let before = engine.applyPlaybackSnapshotCallCount

        let result = session.batch(impact: .snapshotOnly, changed: .selectedTrack) { s in
            s.setSelectedTrackID(trackID)
        }

        XCTAssertTrue(result)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, before)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_drumGroupMappingMutations_publishSnapshotWithoutDocumentApply() throws {
        let groupID = UUID()
        let memberID = UUID()
        let member = StepSequenceTrack(
            id: memberID,
            name: "Kick",
            trackType: .monoMelodic,
            pitches: [36],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let port = MIDIEndpointName(displayName: "Kit Out", isVirtual: false)
        let project = Self.makeDrumGroupProject(
            tracks: [member],
            group: TrackGroup(
                id: groupID,
                name: "Kit",
                memberIDs: [memberID],
                sharedDestination: .midi(port: port, channel: 9, noteOffset: 12),
                triggerMappingMode: .perNote,
                noteMapping: [memberID: 0],
                channelMapping: [memberID: 0]
            )
        )
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        let documentApplyCalls = engine.applyDocumentModelCallCount
        let snapshotApplyCalls = engine.applyPlaybackSnapshotCallCount

        session.setDrumGroupTriggerMappingMode(.perChannel, groupID: groupID)
        session.setDrumGroupMemberNoteOffset(24, trackID: memberID)
        session.setDrumGroupMemberMIDIChannel(4, trackID: memberID)

        XCTAssertEqual(
            engine.applyDocumentModelCallCount,
            documentApplyCalls,
            "Mapping-only drum-group edits must not rebuild the document engine graph"
        )
        XCTAssertGreaterThan(engine.applyPlaybackSnapshotCallCount, snapshotApplyCalls)
        XCTAssertEqual(session.store.trackGroups[0].triggerMappingMode, .perChannel)
        XCTAssertEqual(session.store.trackGroups[0].noteMapping[memberID], 24)
        XCTAssertEqual(session.store.trackGroups[0].channelMapping[memberID], 4)
        XCTAssertEqual(
            session.snapshotPublisher.snapshot.resolvedDestination(for: memberID),
            ResolvedTrackDestination(
                destination: .midi(port: port, channel: 4, noteOffset: 0),
                pitchOffset: 0
            )
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    private static func makeDrumGroupProject(tracks: [StepSequenceTrack], group: TrackGroup) -> Project {
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(tracks: tracks, layers: layers, generatorPool: [], clipPool: [])
        return Project(
            version: 1,
            tracks: tracks,
            trackGroups: [group],
            generatorPool: [],
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [],
            selectedTrackID: tracks[0].id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }
}

@MainActor
private final class DocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
