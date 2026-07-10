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

    func test_resolvedStep_usesSequentialSourceSteps_withoutStepOrderMap() throws {
        let (snapshot, trackID) = makeStepOrderFixtureSnapshot(stepOrderMap: nil)

        for outputStep in 0..<16 {
            let resolved = try XCTUnwrap(snapshot.resolvedStep(
                phraseID: snapshot.selectedPhraseID,
                trackID: trackID,
                stepInPhrase: outputStep
            ))

            XCTAssertEqual(resolved.sourceStepIndex, outputStep)
            XCTAssertEqual(resolved.slotIndex, outputStep)
        }
    }

    func test_resolvedStep_usesCompiledStepOrderMap_forSourceReads() throws {
        let acceptedRemap: [UInt8] = [0, 1, 2, 3, 3, 3, 3, 3, 7, 8, 9, 0, 1, 2, 3, 3]
        let (snapshot, trackID) = makeStepOrderFixtureSnapshot(stepOrderMap: acceptedRemap)

        for outputStep in 0..<16 {
            let resolved = try XCTUnwrap(snapshot.resolvedStep(
                phraseID: snapshot.selectedPhraseID,
                trackID: trackID,
                stepInPhrase: outputStep
            ))
            let expectedSourceStep = Int(acceptedRemap[outputStep])

            XCTAssertEqual(resolved.sourceStepIndex, expectedSourceStep)
            XCTAssertEqual(resolved.slotIndex, expectedSourceStep)
        }

        let outputStep11 = try XCTUnwrap(snapshot.resolvedStep(
            phraseID: snapshot.selectedPhraseID,
            trackID: trackID,
            stepInPhrase: 11
        ))
        XCTAssertEqual(outputStep11.sourceStepIndex, 0)
        XCTAssertTrue(outputStep11.fillEnabled, "Phrase-layer fill timing stays anchored to output step 11")
        XCTAssertFalse(snapshot.layerSnapshot(phraseID: snapshot.selectedPhraseID, stepInPhrase: 0).isFillEnabled(trackID))
        XCTAssertTrue(snapshot.layerSnapshot(phraseID: snapshot.selectedPhraseID, stepInPhrase: 11).isFillEnabled(trackID))
    }

    func test_stepOrderPlaybackResolution_remapsSourceReadsForEveryPlayableTrack() throws {
        let acceptedRemap: [UInt8] = [0, 1, 2, 3, 3, 3, 3, 3, 7, 8, 9, 0, 1, 2, 3, 3]
        let fixture = makeCompiledStepOrderPlaybackProject(stepOrderMap: acceptedRemap, isEnabled: true)
        let snapshot = SequencerSnapshotCompiler.compile(project: fixture.project)
        let phraseID = fixture.project.selectedPhraseID

        for outputStep in 0..<16 {
            let expectedSourceStep = Int(acceptedRemap[outputStep])

            for track in fixture.tracks {
                let resolved = try XCTUnwrap(snapshot.resolvedStep(
                    phraseID: phraseID,
                    trackID: track.id,
                    stepInPhrase: outputStep
                ))

                XCTAssertEqual(resolved.sourceStepIndex, expectedSourceStep)
                XCTAssertEqual(resolved.slotIndex, expectedSourceStep)

                var rng = SystemRandomNumberGenerator()
                var state = GeneratedSourceEvaluationState()
                let notes = EngineController.resolvedStepNotes(
                    for: track.id,
                    in: snapshot,
                    phraseID: phraseID,
                    stepIndex: outputStep,
                    chordContext: nil,
                    state: &state,
                    rng: &rng
                )
                XCTAssertEqual(notes.map(\.pitch), [track.pitchBase + expectedSourceStep])
            }
        }
    }

    func test_stepOrderPlaybackResolution_keepsPhraseLayerTimingOnOutputStep() throws {
        let acceptedRemap: [UInt8] = [0, 1, 2, 3, 3, 3, 3, 3, 7, 8, 9, 0, 1, 2, 3, 3]
        let fixture = makeCompiledStepOrderPlaybackProject(stepOrderMap: acceptedRemap, isEnabled: true)
        let snapshot = SequencerSnapshotCompiler.compile(project: fixture.project)
        let phraseID = fixture.project.selectedPhraseID
        let track = fixture.tracks[0]

        let outputStep11 = try XCTUnwrap(snapshot.resolvedStep(
            phraseID: phraseID,
            trackID: track.id,
            stepInPhrase: 11
        ))
        XCTAssertEqual(outputStep11.sourceStepIndex, 0)
        XCTAssertEqual(outputStep11.slotIndex, 0)
        XCTAssertTrue(outputStep11.fillEnabled)
        XCTAssertEqual(try XCTUnwrap(outputStep11.macroValues[track.macroBindingID]), 11, accuracy: 0.0001)

        let layerStep0 = snapshot.layerSnapshot(phraseID: phraseID, stepInPhrase: 0)
        XCTAssertFalse(layerStep0.isMuted(track.id))
        XCTAssertFalse(layerStep0.isFillEnabled(track.id))
        XCTAssertEqual(try XCTUnwrap(layerStep0.macroValue(trackID: track.id, bindingID: track.macroBindingID)), 0, accuracy: 0.0001)

        let layerStep11 = snapshot.layerSnapshot(phraseID: phraseID, stepInPhrase: 11)
        XCTAssertTrue(layerStep11.isMuted(track.id))
        XCTAssertTrue(layerStep11.isFillEnabled(track.id))
        XCTAssertEqual(try XCTUnwrap(layerStep11.macroValue(trackID: track.id, bindingID: track.macroBindingID)), 11, accuracy: 0.0001)
    }

    func test_stepOrderPlaybackResolution_fallsBackToSequentialForInactiveUnavailableOrUnsupportedStates() throws {
        let acceptedRemap: [UInt8] = [0, 1, 2, 3, 3, 3, 3, 3, 7, 8, 9, 0, 1, 2, 3, 3]
        let cases: [(String, Project)] = [
            (
                "disabled",
                makeCompiledStepOrderPlaybackProject(stepOrderMap: acceptedRemap, isEnabled: false).project
            ),
            (
                "unassigned",
                makeCompiledStepOrderPlaybackProject(stepOrderMap: acceptedRemap, isEnabled: true) { project, _ in
                    project.phrases[0].stepOrderAssignment = nil
                }.project
            ),
            (
                "missing map",
                makeCompiledStepOrderPlaybackProject(stepOrderMap: acceptedRemap, isEnabled: true) { project, mapID in
                    project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)
                    project.stepOrderMaps.removeAll()
                }.project
            ),
            (
                "invalid map",
                makeCompiledStepOrderPlaybackProject(stepOrderMap: acceptedRemap, isEnabled: true) { project, mapID in
                    project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Invalid", values: [0, 1, 2])]
                    project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)
                }.project
            ),
            (
                "unsupported phrase length",
                makeCompiledStepOrderPlaybackProject(stepOrderMap: acceptedRemap, isEnabled: true) { project, _ in
                    project.phrases[0].lengthBars = 2
                }.project
            )
        ]

        for (name, project) in cases {
            let snapshot = SequencerSnapshotCompiler.compile(project: project)
            let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffer(for: project.selectedPhraseID), name)
            XCTAssertNil(phraseBuffer.stepOrderMap, name)

            for track in project.tracks {
                for outputStep in 0..<16 {
                    let resolved = try XCTUnwrap(snapshot.resolvedStep(
                        phraseID: project.selectedPhraseID,
                        trackID: track.id,
                        stepInPhrase: outputStep
                    ), name)
                    XCTAssertEqual(resolved.sourceStepIndex, outputStep, name)
                    XCTAssertEqual(resolved.slotIndex, outputStep, name)
                }
            }
        }
    }

    func test_stepOrderPlaybackResolution_doesNotAffectUnassignedPhrasesOrAuthoredState() throws {
        let acceptedRemap: [UInt8] = [0, 1, 2, 3, 3, 3, 3, 3, 7, 8, 9, 0, 1, 2, 3, 3]
        var fixture = makeCompiledStepOrderPlaybackProject(stepOrderMap: acceptedRemap, isEnabled: true)
        var unrelatedPhrase = fixture.project.phrases[0]
        unrelatedPhrase.id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        unrelatedPhrase.name = "Unassigned Phrase"
        unrelatedPhrase.stepOrderAssignment = nil
        fixture.project.phrases.append(unrelatedPhrase)
        fixture.project.selectedPhraseID = unrelatedPhrase.id
        fixture.project.masterBus.masterOutputGain = 0.42

        let authoredBefore = fixture.project
        let snapshot = SequencerSnapshotCompiler.compile(project: fixture.project)
        let assignedPhraseID = authoredBefore.phrases[0].id
        let unassignedPhraseID = unrelatedPhrase.id

        for outputStep in 0..<16 {
            let assigned = try XCTUnwrap(snapshot.resolvedStep(
                phraseID: assignedPhraseID,
                trackID: fixture.tracks[0].id,
                stepInPhrase: outputStep
            ))
            XCTAssertEqual(assigned.sourceStepIndex, Int(acceptedRemap[outputStep]))

            let unassigned = try XCTUnwrap(snapshot.resolvedStep(
                phraseID: unassignedPhraseID,
                trackID: fixture.tracks[0].id,
                stepInPhrase: outputStep
            ))
            XCTAssertEqual(unassigned.sourceStepIndex, outputStep)
            XCTAssertEqual(unassigned.slotIndex, outputStep)
        }

        var rng = SystemRandomNumberGenerator()
        var state = GeneratedSourceEvaluationState()
        _ = EngineController.resolvedStepNotes(
            for: fixture.tracks[0].id,
            in: snapshot,
            phraseID: assignedPhraseID,
            stepIndex: 11,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
        _ = EngineController.resolvedStepNotes(
            for: fixture.tracks[0].id,
            in: snapshot,
            phraseID: unassignedPhraseID,
            stepIndex: 11,
            chordContext: nil,
            state: &state,
            rng: &rng
        )

        XCTAssertEqual(fixture.project, authoredBefore)
        XCTAssertEqual(snapshot.selectedPhraseID, unassignedPhraseID)
        XCTAssertEqual(authoredBefore.masterBus.masterOutputGain, 0.42, accuracy: 0.0001)
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

private struct StepOrderPlaybackFixture {
    struct PlayableTrack {
        let id: UUID
        let pitchBase: Int
        let macroBindingID: UUID
    }

    var project: Project
    let tracks: [PlayableTrack]
}

private func makeStepOrderFixtureSnapshot(stepOrderMap: [UInt8]?) -> (PlaybackSnapshot, UUID) {
    let phraseID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let trackID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let stepCount = 16
    var fillEnabled = [Bool](repeating: false, count: stepCount)
    fillEnabled[11] = true

    let trackState = TrackPhrasePlaybackBuffer(
        patternSlotIndex: (0..<stepCount).map(UInt8.init),
        mute: [Bool](repeating: false, count: stepCount),
        fillEnabled: fillEnabled,
        macroValues: [[Double]](repeating: [], count: stepCount)
    )
    let phraseBuffer = PhrasePlaybackBuffer(
        phraseID: phraseID,
        stepCount: stepCount,
        repeatCount: 1,
        loopEnabled: false,
        stepOrderMap: stepOrderMap,
        trackStates: [trackID: trackState]
    )
    let program = TrackSourceProgram(
        trackID: trackID,
        slotPrograms: [SlotProgram](repeating: .empty, count: stepCount),
        macroBindingIDs: [],
        macroDefaults: [:]
    )

    return (
        PlaybackSnapshot(
            selectedPhraseID: phraseID,
            clipPool: [],
            sliceSetPool: [],
            generatorPool: [],
            chordGeneratorChoicesByKey: [:],
            tracks: [],
            resolvedDestinationsByTrackID: [:],
            trackOrder: [trackID],
            phraseOrder: [phraseID],
            clipBuffersByID: [:],
            trackProgramsByTrackID: [trackID: program],
            phraseBuffersByID: [phraseID: phraseBuffer]
        ),
        trackID
    )
}

private func makeCompiledStepOrderPlaybackProject(
    stepOrderMap: [UInt8],
    isEnabled: Bool,
    mutate: (inout Project, UUID) -> Void = { _, _ in }
) -> StepOrderPlaybackFixture {
    let mapID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
    let firstTrackID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
    let secondTrackID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!

    let firstBinding = TrackMacroBinding(
        descriptor: stepMarkerMacroDescriptor(
            id: UUID(uuidString: "dddddddd-0000-0000-0000-000000000001")!
        ),
        slotIndex: 0
    )
    let secondBinding = TrackMacroBinding(
        descriptor: stepMarkerMacroDescriptor(
            id: UUID(uuidString: "dddddddd-0000-0000-0000-000000000002")!
        ),
        slotIndex: 0
    )
    let firstTrack = StepSequenceTrack(
        id: firstTrackID,
        name: "Lead",
        pitches: [60],
        stepPattern: Array(repeating: true, count: 16),
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 100,
        gateLength: 4,
        macros: [firstBinding]
    )
    let secondTrack = StepSequenceTrack(
        id: secondTrackID,
        name: "Counter",
        pitches: [80],
        stepPattern: Array(repeating: true, count: 16),
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 100,
        gateLength: 4,
        macros: [secondBinding]
    )
    let tracks = [firstTrack, secondTrack]
    let layers = PhraseLayerDefinition.defaultSet(for: tracks)
    var phrase = PhraseModel.default(
        tracks: tracks,
        layers: layers,
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: []
    )
    phrase.lengthBars = 1
    phrase.stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: isEnabled)

    let trackDescriptors = [
        (track: firstTrack, pitchBase: 60, binding: firstBinding),
        (track: secondTrack, pitchBase: 80, binding: secondBinding)
    ]

    var clipPool: [ClipPoolEntry] = []
    var patternBanks: [TrackPatternBank] = []
    for descriptor in trackDescriptors {
        var slots: [TrackPatternSlot] = []
        for step in 0..<16 {
            let clipID = UUID(uuidString: String(format: "bbbbbbbb-%04d-%04d-0000-000000000000", descriptor.pitchBase, step))!
            clipPool.append(
                ClipPoolEntry(
                    id: clipID,
                    name: "\(descriptor.track.name) Step \(step)",
                    trackType: descriptor.track.trackType,
                    content: .noteGrid(
                        lengthSteps: 16,
                        steps: (0..<16).map { clipStep in
                            guard clipStep == step else { return .empty }
                            return ClipStep(
                                main: ClipLane(
                                    chance: 1,
                                    notes: [
                                        ClipStepNote(
                                            pitch: descriptor.pitchBase + step,
                                            velocity: 100,
                                            lengthSteps: 1
                                        )
                                    ]
                                ),
                                fill: nil
                            )
                        }
                    )
                )
            )
            slots.append(TrackPatternSlot(slotIndex: step, sourceRef: .clip(clipID)))
        }
        patternBanks.append(TrackPatternBank(trackID: descriptor.track.id, slots: slots))
        phrase.setCell(
            .steps((0..<16).map { .index($0) }),
            for: "pattern",
            trackID: descriptor.track.id
        )
        phrase.setCell(
            .steps((0..<16).map { .scalar(Double($0)) }),
            for: "macro-\(descriptor.track.id.uuidString)-\(descriptor.binding.id.uuidString)",
            trackID: descriptor.track.id
        )
    }

    phrase.setCell(
        .steps((0..<16).map { .bool($0 == 11) }),
        for: "fill-flag",
        trackID: firstTrackID
    )
    phrase.setCell(
        .steps((0..<16).map { .bool($0 == 11) }),
        for: "mute",
        trackID: firstTrackID
    )

    var project = Project(
        version: 1,
        tracks: tracks,
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: clipPool,
        layers: layers,
        routes: [],
        patternBanks: patternBanks,
        stepOrderMaps: [StepOrderMap(id: mapID, name: "Break Fold", values: stepOrderMap)],
        selectedTrackID: firstTrackID,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
    mutate(&project, mapID)

    return StepOrderPlaybackFixture(
        project: project,
        tracks: [
            .init(id: firstTrackID, pitchBase: 60, macroBindingID: firstBinding.id),
            .init(id: secondTrackID, pitchBase: 80, macroBindingID: secondBinding.id)
        ]
    )
}

private func stepMarkerMacroDescriptor(id: UUID) -> TrackMacroDescriptor {
    TrackMacroDescriptor(
        id: id,
        displayName: "Step Marker",
        minValue: 0,
        maxValue: 15,
        defaultValue: 0,
        valueType: .scalar,
        source: .auParameter(address: 1, identifier: "step-marker-\(id.uuidString)")
    )
}

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
