import XCTest
@testable import SequencerAI

@MainActor
final class IncrementalCompileEquivalenceTests: XCTestCase {

    func test_clipChange_matchesFullCompileOracle() throws {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        store.mutateClip(id: clipID) { clip in
            clip.content = .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(
                    main: ClipLane(
                        chance: 1,
                        notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]
                    ),
                    fill: nil
                )]
            )
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .clip(clipID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_phraseChange_matchesFullCompileOracle() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let phraseID = try XCTUnwrap(store.phrases.first?.id)
        let muteLayerID = try XCTUnwrap(store.layers.first(where: { $0.target == .mute })?.id)

        store.mutatePhrase(id: phraseID) { phrase in
            phrase.setCell(.single(.bool(true)), for: muteLayerID, trackID: trackID)
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .phrase(phraseID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_patternBankChange_matchesFullCompileOracle() throws {
        let (baseProject, trackID, clipID) = makeLiveStoreProject()
        let alternateClipID = UUID(uuidString: "99999999-2222-3333-4444-555555555555")!
        let alternateClip = ClipPoolEntry(
            id: alternateClipID,
            name: "Alt Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(
                    main: ClipLane(
                        chance: 1,
                        notes: [ClipStepNote(pitch: 84, velocity: 100, lengthSteps: 4)]
                    ),
                    fill: nil
                )]
            )
        )

        var project = baseProject
        project.clipPool.append(alternateClip)
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        XCTAssertEqual(previous.clipEntry(id: clipID)?.pitchPool, [60])

        store.mutatePatternBank(trackID: trackID) { bank in
            bank.setSlot(
                TrackPatternSlot(slotIndex: 0, sourceRef: .clip(alternateClipID)),
                at: 0
            )
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .patternBank(trackID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_selectedPhraseChange_reusesExistingBuffers() throws {
        let (baseProject, _, _) = makeLiveStoreProject()
        var project = baseProject
        let originalPhraseID = project.selectedPhraseID
        project.duplicatePhrase(id: originalPhraseID)
        let phrase = try XCTUnwrap(project.phrases.last)
        project.selectedPhraseID = project.phrases[0].id
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        store.setSelectedPhraseID(phrase.id)

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .selectedPhrase,
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
        XCTAssertEqual(incremental.selectedPhraseID, phrase.id)
        XCTAssertEqual(incremental.clipBuffersByID, previous.clipBuffersByID)
        XCTAssertEqual(incremental.trackProgramsByTrackID, previous.trackProgramsByTrackID)
        XCTAssertEqual(incremental.phraseBuffersByID, previous.phraseBuffersByID)
    }

    func test_generatorChange_matchesFullCompileOracle() throws {
        let (project, _, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let generatorID = try XCTUnwrap(store.generatorPool.first?.id)

        store.mutateGenerator(id: generatorID) { generator in
            generator.name = "Renamed Generator"
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .generator(generatorID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_trackMetadataChange_matchesFullCompileOracle() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        store.mutateTrack(id: trackID) { track in
            track.name = "Renamed Track"
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .track(trackID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_trackMacroShapeChange_matchesFullCompileOracle() throws {
        let (project, trackID, clipID) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let binding = TrackMacroBinding(descriptor: Self.testMacroDescriptor())

        store.mutateTrack(id: trackID) { track in
            track.macros.append(binding)
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .track(trackID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
        XCTAssertEqual(incremental.trackProgramsByTrackID[trackID]?.macroBindingIDs, [binding.id])
        XCTAssertEqual(incremental.clipBuffersByID[clipID]?.macroBindingOrder, [binding.id])
    }

    func test_layersChange_matchesFullCompileOracle() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        var layers = store.layers
        let muteIndex = try XCTUnwrap(layers.firstIndex(where: { $0.target == .mute }))
        layers[muteIndex].defaults[trackID] = .bool(true)

        store.setLayers(layers)

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .layers,
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_bulkChange_matchesFullCompileOracle() throws {
        let (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60)
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let phraseID = try XCTUnwrap(store.phrases.first?.id)
        let muteLayerID = try XCTUnwrap(store.layers.first(where: { $0.target == .mute })?.id)

        store.mutateClip(id: clipID) { clip in
            clip.name = "Bulk Clip"
        }
        store.mutatePhrase(id: phraseID) { phrase in
            phrase.setCell(.single(.bool(true)), for: muteLayerID, trackID: trackID)
        }
        store.mutateTrack(id: trackID) { track in
            track.velocity = 80
        }

        let change = SnapshotChange.clip(clipID)
            .union(.phrase(phraseID))
            .union(.track(trackID))
        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: change,
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_fullRebuildChange_matchesFullCompileOracle() throws {
        let (project, _, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        store.importFromProject({
            var next = project
            next.appendTrack(trackType: .monoMelodic)
            return next
        }())

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .full,
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    private static func testMacroDescriptor() -> TrackMacroDescriptor {
        TrackMacroDescriptor(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            displayName: "Test Macro",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 7, identifier: "test")
        )
    }

    // MARK: - CR2-3 regression: incremental path resolves clip macro lanes by ownerTrackID

    /// Two `monoMelodic` tracks each own a clip with per-step macro lanes.
    /// The *incremental* compile path must resolve `macroBindingOrder` per clip
    /// using the owner-track lookup — the same guarantee the primary path provides
    /// (tested in `SequencerSnapshotCompilerSemanticsTests`).
    ///
    /// Before the C1 fix the primary path used `tracks.first(where: { trackType == clip.trackType })`
    /// which is non-deterministic when two tracks share a type. The incremental path
    /// shares the same `clipOwnerByID` lookup, so this test guards against a regression
    /// where the incremental path could be authored independently and lose the fix.
    func test_twoMonoMelodicTracks_incrementalPath_resolvesMacroBindingsPerOwnerTrack() throws {
        let trackAID   = UUID(uuidString: "aaaaaaaa-0001-0000-0000-000000000001")!
        let trackBID   = UUID(uuidString: "bbbbbbbb-0001-0000-0000-000000000001")!
        let clipAID    = UUID(uuidString: "aaaaaaaa-0001-0000-0000-000000000002")!
        let clipBID    = UUID(uuidString: "bbbbbbbb-0001-0000-0000-000000000002")!
        let bindingAID = UUID(uuidString: "aaaaaaaa-0001-0000-0000-000000000003")!
        let bindingBID = UUID(uuidString: "bbbbbbbb-0001-0000-0000-000000000003")!

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

        let trackA = StepSequenceTrack(
            id: trackAID, name: "TrackA", pitches: [60], stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 96, gateLength: 4,
            macros: [TrackMacroBinding(descriptor: descriptorA, slotIndex: 0)]
        )
        let trackB = StepSequenceTrack(
            id: trackBID, name: "TrackB", pitches: [60], stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 96, gateLength: 4,
            macros: [TrackMacroBinding(descriptor: descriptorB, slotIndex: 0)]
        )

        let clipA = ClipPoolEntry(
            id: clipAID, name: "ClipA", trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: 2, steps: [
                ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 1)]), fill: nil),
                .empty
            ]),
            macroLanes: [bindingAID: MacroLane(values: [0.25, nil])]
        )
        let clipB = ClipPoolEntry(
            id: clipBID, name: "ClipB", trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: 2, steps: [
                ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 64, velocity: 100, lengthSteps: 1)]), fill: nil),
                .empty
            ]),
            macroLanes: [bindingBID: MacroLane(values: [0.75, nil])]
        )

        let bankA = TrackPatternBank(trackID: trackAID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipAID))])
        let bankB = TrackPatternBank(trackID: trackBID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipBID))])
        let layers = PhraseLayerDefinition.defaultSet(for: [trackA, trackB])
        let phrase = PhraseModel.default(tracks: [trackA, trackB], layers: layers, generatorPool: [], clipPool: [clipA, clipB])
        let project = Project(
            version: 1, tracks: [trackA, trackB], generatorPool: [], clipPool: [clipA, clipB],
            layers: layers, routes: [], patternBanks: [bankA, bankB],
            selectedTrackID: trackAID, phrases: [phrase], selectedPhraseID: phrase.id
        )

        let store = LiveSequencerStore(project: project)
        // Build the initial snapshot the incremental path will diff against.
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        // Trigger an incremental recompile by mutating trackA — this exercises the
        // incremental path's clipOwnerByID lookup for clips that belong to changed tracks.
        store.mutateTrack(id: trackAID) { track in
            track.velocity = 80
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .track(trackAID),
            previous: previous,
            state: state
        )

        // The incremental result must equal the full compile oracle.
        XCTAssertEqual(incremental, expected,
            "Incremental compile must equal full compile oracle for two-track shared-type scenario")

        // ClipA's buffer must carry bindingAID (TrackA's macro) and not bindingBID.
        let bufferA = try XCTUnwrap(incremental.clipBuffersByID[clipAID], "ClipA buffer must exist")
        XCTAssertTrue(bufferA.macroBindingOrder.contains(bindingAID),
            "ClipA buffer must include TrackA's binding in incremental path")
        XCTAssertFalse(bufferA.macroBindingOrder.contains(bindingBID),
            "ClipA buffer must not include TrackB's binding in incremental path")

        // ClipB's buffer must carry bindingBID (TrackB's macro) and not bindingAID.
        let bufferB = try XCTUnwrap(incremental.clipBuffersByID[clipBID], "ClipB buffer must exist")
        XCTAssertTrue(bufferB.macroBindingOrder.contains(bindingBID),
            "ClipB buffer must include TrackB's binding in incremental path")
        XCTAssertFalse(bufferB.macroBindingOrder.contains(bindingAID),
            "ClipB buffer must not include TrackA's binding in incremental path")
    }
}
