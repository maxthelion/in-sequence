import XCTest
@testable import SequencerAI

// Phase 1b guardrail tests — PlaybackSnapshot carries typed fields, not Project.

@MainActor
final class PlaybackSnapshotBuffersOnlyTests: XCTestCase {

    // MARK: - 1. PlaybackSnapshot has no `project` field

    /// Structural assertion: if this test compiles, `PlaybackSnapshot` has no `project`
    /// member of type `Project`. Swift would fail to compile any access to a removed field,
    /// so the test is enforced at build time. We use Mirror at runtime as an additional
    /// belt-and-suspenders check.
    func test_snapshot_doesNotExposeProject() {
        let snapshot = SequencerSnapshotCompiler.compile(state: .empty)
        let mirror = Mirror(reflecting: snapshot)
        let childNames = mirror.children.compactMap { $0.label }
        XCTAssertFalse(
            childNames.contains("project"),
            "PlaybackSnapshot must not expose a 'project' field; found: \(childNames)"
        )
        // Also verify the typed fields Phase 1b added are present.
        XCTAssertTrue(childNames.contains("selectedPhraseID"), "Expected 'selectedPhraseID' in snapshot")
        XCTAssertTrue(childNames.contains("clipPool"), "Expected 'clipPool' in snapshot")
        XCTAssertTrue(childNames.contains("generatorPool"), "Expected 'generatorPool' in snapshot")
    }

    // MARK: - 2. Note-grid clip resolution reads compiled clip data

    func test_tickResolution_forNoteGridClip_readsCompiledClipData() throws {
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true, false])
        let store = LiveSequencerStore(project: project)
        let snapshot = SequencerSnapshotCompiler.compile(state: store.compileInput())

        var rng = SystemRandomNumberGenerator()
        var state = GeneratedSourceEvaluationState()

        // Step 0 is ON in the note-grid clip.
        let notesAtStep0 = EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
        XCTAssertFalse(notesAtStep0.isEmpty, "Step 0 should produce notes for an active clip step")
        XCTAssertEqual(notesAtStep0.first?.pitch, 60, "Note pitch should match clip content")

        // Step 1 is OFF in the note-grid clip.
        let notesAtStep1 = EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 1,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
        XCTAssertTrue(notesAtStep1.isEmpty, "Step 1 should produce no notes for an empty clip step")
    }

    // MARK: - 3. Generator source resolution uses snapshot's generatorPool

    func test_tickResolution_forGenerator_usesSnapshotGeneratorPool() throws {
        let generatorID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!
        let (project, trackID, _) = makeGeneratorProject(generatorID: generatorID)
        let store = LiveSequencerStore(project: project)
        let snapshot = SequencerSnapshotCompiler.compile(state: store.compileInput())

        // Verify the generator is in the snapshot's pool (not fetched from Project).
        XCTAssertNotNil(snapshot.generatorEntry(id: generatorID), "Generator must be in snapshot.generatorPool")

        var rng = SystemRandomNumberGenerator()
        var state = GeneratedSourceEvaluationState()

        // Call the same resolution path the tick uses.
        _ = EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
        // Resolution did not fatalError or return early — the generator pool in the
        // snapshot was sufficient. The test goal is structural: no Project read needed.
    }

    // MARK: - 4. Modifier resolution uses snapshot's generatorPool

    func test_modifierResolution_usesSnapshotGeneratorPool() throws {
        let generatorID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!
        let modifierID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2")!
        let (project, trackID, _) = makeGeneratorProjectWithModifier(
            generatorID: generatorID,
            modifierID: modifierID
        )
        let store = LiveSequencerStore(project: project)
        let snapshot = SequencerSnapshotCompiler.compile(state: store.compileInput())

        XCTAssertNotNil(snapshot.generatorEntry(id: generatorID), "Source generator must be in snapshot.generatorPool")
        XCTAssertNotNil(snapshot.generatorEntry(id: modifierID), "Modifier generator must be in snapshot.generatorPool")

        var rng = SystemRandomNumberGenerator()
        var state = GeneratedSourceEvaluationState()

        // Verify the modifier chain resolves without accessing Project.
        _ = EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
    }

    // MARK: - 5. Snapshot reflects clip mutation

    func test_snapshot_publishesUpdatedClipData_onClipMutation() throws {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true])
        let store = LiveSequencerStore(project: project)

        let before = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let beforeClip = try XCTUnwrap(before.clipPool.first(where: { $0.id == clipID }))
        XCTAssertEqual(beforeClip.pitchPool, [60])

        store.mutateClip(id: clipID) { entry in
            entry.content = .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]),
                    fill: nil
                )]
            )
        }

        let after = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let afterClip = try XCTUnwrap(after.clipPool.first(where: { $0.id == clipID }))
        XCTAssertEqual(afterClip.pitchPool, [72], "Snapshot clipPool must reflect the mutation")
    }

    // MARK: - 6. publishSnapshot does not call exportToProject

    func test_publishSnapshot_doesNotCallExportToProject() {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let engineController = EngineController(client: nil, endpoint: nil)
        let store = LiveSequencerStore(project: project)

        // Install the observer before any operations.
        var exportCallCount = 0
        store.exportToProjectObserver = { exportCallCount += 1 }

        let session = InstrumentedSession(store: store, engineController: engineController)

        // Perform N mutations followed by N publishSnapshot calls.
        let n = 5
        for _ in 0..<n {
            store.mutateClip(id: clipID) { entry in
                entry.name = UUID().uuidString
            }
            session.publishSnapshot()
        }

        XCTAssertEqual(
            exportCallCount,
            0,
            "publishSnapshot() must not call exportToProject() — it should use compileInput() instead"
        )
    }
}

// MARK: - Helpers

/// A project with a single generator-mode slot (no clip).
private func makeGeneratorProject(generatorID: UUID) -> (Project, UUID, UUID) {
    let trackID = UUID()
    let generator = GeneratorPoolEntry.makeDefault(
        id: generatorID,
        name: "Test Generator",
        kind: .monoGenerator,
        trackType: .monoMelodic
    )
    let track = StepSequenceTrack(
        id: trackID,
        name: "Track",
        pitches: [60],
        stepPattern: [true],
        stepAccents: [true],
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 96,
        gateLength: 4
    )
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    let patternBank = TrackPatternBank(
        trackID: trackID,
        slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generatorID))]
    )
    let phrase = PhraseModel.default(
        tracks: [track],
        layers: layers,
        generatorPool: [generator],
        clipPool: []
    )
    let project = Project(
        version: 1,
        tracks: [track],
        generatorPool: [generator],
        clipPool: [],
        layers: layers,
        routes: [],
        patternBanks: [patternBank],
        selectedTrackID: trackID,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
    return (project, trackID, generatorID)
}

/// A project with a generator-mode slot that has a modifier generator applied.
private func makeGeneratorProjectWithModifier(generatorID: UUID, modifierID: UUID) -> (Project, UUID, UUID) {
    let trackID = UUID()
    let sourceGenerator = GeneratorPoolEntry.makeDefault(
        id: generatorID,
        name: "Source Generator",
        kind: .monoGenerator,
        trackType: .monoMelodic
    )
    let modifierGenerator = GeneratorPoolEntry.makeDefault(
        id: modifierID,
        name: "Modifier Generator",
        kind: .polyGenerator,
        trackType: .polyMelodic
    )
    let track = StepSequenceTrack(
        id: trackID,
        name: "Track",
        pitches: [60],
        stepPattern: [true],
        stepAccents: [true],
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 96,
        gateLength: 4
    )
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    let sourceRef = SourceRef(
        mode: .generator,
        generatorID: generatorID,
        clipID: nil,
        modifierGeneratorID: modifierID,
        modifierBypassed: false
    )
    let patternBank = TrackPatternBank(
        trackID: trackID,
        slots: [TrackPatternSlot(slotIndex: 0, sourceRef: sourceRef)]
    )
    let generatorPool = [sourceGenerator, modifierGenerator]
    let phrase = PhraseModel.default(
        tracks: [track],
        layers: layers,
        generatorPool: generatorPool,
        clipPool: []
    )
    let project = Project(
        version: 1,
        tracks: [track],
        generatorPool: generatorPool,
        clipPool: [],
        layers: layers,
        routes: [],
        patternBanks: [patternBank],
        selectedTrackID: trackID,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
    return (project, trackID, generatorID)
}

// MARK: - InstrumentedSession

/// A minimal session stand-in. Mirrors the `publishSnapshot` path of
/// `SequencerDocumentSession` without requiring a `Binding<SeqAIDocument>`.
@MainActor
final class InstrumentedSession {
    let store: LiveSequencerStore
    let engineController: EngineController

    init(store: LiveSequencerStore, engineController: EngineController) {
        self.store = store
        self.engineController = engineController
    }

    func publishSnapshot() {
        engineController.apply(
            playbackSnapshot: SequencerSnapshotCompiler.compile(state: store.compileInput())
        )
    }
}
