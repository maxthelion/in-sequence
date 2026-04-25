import XCTest
@testable import SequencerAI

final class SequencerSnapshotCompilerSemanticsTests: XCTestCase {

    // MARK: - Existing: note-grid and per-step pattern selection

    func test_compiler_uses_note_grid_and_exact_step_pattern_selection() throws {
        let macroDescriptor = TrackMacroDescriptor.builtin(
            trackID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            kind: .sampleGain
        )
        let binding = TrackMacroBinding(descriptor: macroDescriptor)
        var (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60, macros: [binding])

        project.updateClipEntry(id: clipID) { entry in
            entry.macroLanes[binding.id] = MacroLane(values: [nil, 0.75])
        }
        project.setPhraseCell(
            .steps([.index(0), .index(1)]),
            layerID: "pattern",
            trackIDs: [trackID],
            phraseID: project.selectedPhraseID
        )

        let altClipID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        project.clipPool.append(
            ClipPoolEntry(
                id: altClipID,
                name: "Alt",
                trackType: .monoMelodic,
                content: .noteGrid(
                    lengthSteps: 2,
                    steps: [
                        ClipStep(main: ClipLane(chance: 0.5, notes: [ClipStepNote(pitch: 72, velocity: 91, lengthSteps: 5)]), fill: nil),
                        .empty
                    ]
                )
            )
        )
        project.setPatternClipID(altClipID, for: trackID, slotIndex: 1)

        let snapshot = SequencerSnapshotCompiler.compile(project: project)

        let clipBuffer = try XCTUnwrap(snapshot.clipBuffersByID[clipID])
        XCTAssertEqual(clipBuffer.steps.first?.main?.notes.first?.pitch, 60)
        XCTAssertEqual(clipBuffer.macroOverrides(at: 1)[binding.id], 0.75)

        let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffersByID[project.selectedPhraseID])
        let trackState = try XCTUnwrap(phraseBuffer.trackState(for: trackID))
        XCTAssertEqual(Array(trackState.patternSlotIndex.prefix(2)), [0, 1])
    }

    // MARK: - New: generator source resolves via snapshot generator pool

    /// A slot with `.generator` source compiles to a `.generator` SlotProgram that
    /// references the correct generator ID from the snapshot's generator pool.
    func test_generatorSource_resolvesViaSnapshotGeneratorPool() throws {
        let generatorID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000001")!
        let trackID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!

        let generator = GeneratorPoolEntry.makeDefault(
            id: generatorID,
            name: "Test Gen",
            kind: .monoGenerator,
            trackType: .monoMelodic
        )
        let track = StepSequenceTrack(
            id: trackID,
            name: "Track",
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 96,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let patternBank = TrackPatternBank(
            trackID: trackID,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generatorID))]
        )
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [])
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

        let snapshot = SequencerSnapshotCompiler.compile(project: project)

        // The generator is present in the snapshot's pool.
        XCTAssertNotNil(snapshot.generatorEntry(id: generatorID), "generator must appear in snapshot.generatorPool")

        // The compiled slot program references the generator.
        let program = try XCTUnwrap(snapshot.sourceProgram(for: trackID))
        if case let .generator(compiledGenID, _, _) = program.slotProgram(at: 0) {
            XCTAssertEqual(compiledGenID, generatorID, "compiled slot must reference the correct generator ID")
        } else {
            XCTFail("slot 0 should be a .generator slot, got: \(program.slotProgram(at: 0))")
        }
    }

    // MARK: - New: modifier present in compiled slot program

    /// A slot with a clip source AND a modifier generator compiles to a `.clip` SlotProgram
    /// with the modifier ID set and `modifierBypassed: false`.
    func test_modifier_presentInCompiledSlotProgram_whenNotBypassed() throws {
        let trackID = UUID(uuidString: "cccccccc-0000-0000-0000-000000000001")!
        let clipID  = UUID(uuidString: "cccccccc-0000-0000-0000-000000000002")!
        let modID   = UUID(uuidString: "cccccccc-0000-0000-0000-000000000003")!

        let modifier = GeneratorPoolEntry.makeDefault(id: modID, name: "Mod", kind: .monoGenerator, trackType: .monoMelodic)
        let track = StepSequenceTrack(
            id: trackID, name: "T", pitches: [60], stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 96, gateLength: 4
        )
        let clip = ClipPoolEntry(
            id: clipID, name: "C", trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: 1, steps: [
                ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 1)]), fill: nil)
            ])
        )
        let sourceRef = SourceRef(mode: .clip, clipID: clipID, modifierGeneratorID: modID, modifierBypassed: false)
        let bank = TrackPatternBank(trackID: trackID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: sourceRef)])
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [modifier], clipPool: [clip])
        let project = Project(
            version: 1, tracks: [track], generatorPool: [modifier], clipPool: [clip],
            layers: layers, routes: [], patternBanks: [bank],
            selectedTrackID: trackID, phrases: [phrase], selectedPhraseID: phrase.id
        )

        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let program = try XCTUnwrap(snapshot.sourceProgram(for: trackID))

        if case let .clip(compiledClipID, compiledModID, bypassed) = program.slotProgram(at: 0) {
            XCTAssertEqual(compiledClipID, clipID, "compiled clip ID must match")
            XCTAssertEqual(compiledModID, modID, "compiled modifier generator ID must match")
            XCTAssertFalse(bypassed, "modifier must not be bypassed")
        } else {
            XCTFail("slot 0 should be a .clip slot, got: \(program.slotProgram(at: 0))")
        }
    }

    // MARK: - New: modifier bypassed in compiled slot program

    /// A slot with `modifierBypassed: true` compiles to a `.clip` SlotProgram with
    /// `modifierBypassed: true`.
    func test_modifierBypassed_compilesToBypassedSlotProgram() throws {
        let trackID = UUID(uuidString: "dddddddd-0000-0000-0000-000000000001")!
        let clipID  = UUID(uuidString: "dddddddd-0000-0000-0000-000000000002")!
        let modID   = UUID(uuidString: "dddddddd-0000-0000-0000-000000000003")!

        let modifier = GeneratorPoolEntry.makeDefault(id: modID, name: "Mod", kind: .monoGenerator, trackType: .monoMelodic)
        let track = StepSequenceTrack(
            id: trackID, name: "T", pitches: [60], stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 96, gateLength: 4
        )
        let clip = ClipPoolEntry(
            id: clipID, name: "C", trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: 1, steps: [
                ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 1)]), fill: nil)
            ])
        )
        // Same as above but modifierBypassed: true.
        let sourceRef = SourceRef(mode: .clip, clipID: clipID, modifierGeneratorID: modID, modifierBypassed: true)
        let bank = TrackPatternBank(trackID: trackID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: sourceRef)])
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [modifier], clipPool: [clip])
        let project = Project(
            version: 1, tracks: [track], generatorPool: [modifier], clipPool: [clip],
            layers: layers, routes: [], patternBanks: [bank],
            selectedTrackID: trackID, phrases: [phrase], selectedPhraseID: phrase.id
        )

        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let program = try XCTUnwrap(snapshot.sourceProgram(for: trackID))

        if case let .clip(_, _, bypassed) = program.slotProgram(at: 0) {
            XCTAssertTrue(bypassed, "modifier must be marked bypassed in compiled slot program")
        } else {
            XCTFail("slot 0 should be a .clip slot, got: \(program.slotProgram(at: 0))")
        }
    }

    // MARK: - New: clip-step macro override beats phrase-step which beats default

    /// At a step that has all three levels of macro value (descriptor default, phrase-step
    /// value, and clip-step override), the clip-step override wins.
    ///
    /// Setup:
    ///   - descriptor default = 0.1
    ///   - phrase step 0 value = 0.5 (via .single scalar layer)
    ///   - clip step 0 macro lane override = 0.9
    ///
    /// resolvedStep at step 0 should yield 0.9 (clip wins over phrase wins over default).
    func test_macroPrecedence_clipStepOverride_wins_overPhraseStep_overDefault() throws {
        let trackID   = UUID(uuidString: "eeeeeeee-0000-0000-0000-000000000001")!
        let clipID    = UUID(uuidString: "eeeeeeee-0000-0000-0000-000000000002")!
        let bindingID = UUID(uuidString: "eeeeeeee-0000-0000-0000-000000000003")!

        let descriptor = TrackMacroDescriptor(
            id: bindingID,
            displayName: "Test",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.1,    // Level 1: default
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "p")
        )
        let track = StepSequenceTrack(
            id: trackID, name: "T", pitches: [60], stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 96, gateLength: 4,
            macros: [TrackMacroBinding(descriptor: descriptor)]
        )

        // Clip step 0 override = 0.9 (Level 3 — wins).
        let clip = ClipPoolEntry(
            id: clipID, name: "C", trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: 2, steps: [
                ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 1)]), fill: nil),
                .empty
            ]),
            macroLanes: [bindingID: MacroLane(values: [0.9, nil])]
        )
        let bank = TrackPatternBank(trackID: trackID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipID))])

        // Build layers from the track's macros so syncMacroLayers can sync the phrase.
        let initialLayers = PhraseLayerDefinition.defaultSet(for: [track])
        let initialPhrase = PhraseModel.default(tracks: [track], layers: initialLayers, generatorPool: [], clipPool: [clip])
        var project = Project(
            version: 1, tracks: [track], generatorPool: [], clipPool: [clip],
            layers: initialLayers, routes: [], patternBanks: [bank],
            selectedTrackID: trackID,
            phrases: [initialPhrase],
            selectedPhraseID: initialPhrase.id
        )
        project.syncMacroLayers()

        // Phrase step 0 value = 0.5 (Level 2 — beats default but loses to clip override).
        let phraseLayerID = project.layers.first(where: { layer in
            guard case let .macroParam(tid, bid) = layer.target else { return false }
            return tid == trackID && bid == bindingID
        })?.id
        if let phraseLayerID {
            project.setPhraseCell(
                PhraseCell.single(PhraseCellValue.scalar(0.5)),
                layerID: phraseLayerID,
                trackIDs: [trackID],
                phraseID: project.selectedPhraseID
            )
        } else {
            XCTFail("Expected a macroParam layer for the binding; syncMacroLayers may not have run")
            return
        }

        let snapshot = SequencerSnapshotCompiler.compile(project: project)

        // Resolve step 0.
        let resolved: ResolvedTrackPlaybackStep = try XCTUnwrap(
            snapshot.resolvedStep(phraseID: snapshot.selectedPhraseID, trackID: trackID, stepInPhrase: 0),
            "resolvedStep must not be nil for step 0"
        )

        let resolvedValue = resolved.macroValues[bindingID]

        // Clip override (0.9) must win over phrase value (0.5) and default (0.1).
        XCTAssertEqual(resolvedValue ?? -1, 0.9, accuracy: 0.001,
            "clip-step macro override (0.9) must win over phrase-step (0.5) and default (0.1); got \(resolvedValue as Any)")

        // Confirm phrase-step (0.5) would win over default (0.1) when no clip override is present.
        // Resolve step 1 — no clip override there (nil in the macro lane).
        let resolvedStep1: ResolvedTrackPlaybackStep = try XCTUnwrap(
            snapshot.resolvedStep(phraseID: snapshot.selectedPhraseID, trackID: trackID, stepInPhrase: 1),
            "resolvedStep must not be nil for step 1"
        )
        let valueAtStep1 = resolvedStep1.macroValues[bindingID]
        // .single cell applies to all steps, so phrase value (0.5) should win over default (0.1).
        XCTAssertEqual(valueAtStep1 ?? -1, 0.5, accuracy: 0.001,
            "phrase-step macro value (0.5) must beat descriptor default (0.1) when no clip override; got \(valueAtStep1 as Any)")
    }

    // MARK: - C1 regression: two monoMelodic tracks each resolve their own macro bindings

    /// Two `monoMelodic` tracks each have their own clip, their own AU macro binding
    /// (different UUIDs), and a per-step lane on that clip.
    ///
    /// Before the C1 fix, `compileClipBuffer` resolved `macroBindingOrder` using
    /// `tracks.first(where: { $0.trackType == clip.trackType })` — non-deterministic
    /// when two tracks share a type. After the fix it uses the ownerTrackID from
    /// the pattern bank, so each clip's buffer carries its own track's binding IDs.
    func test_twoMonoMelodicTracks_eachResolveOwnMacroBindings() throws {
        let trackAID  = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
        let trackBID  = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000001")!
        let clipAID   = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!
        let clipBID   = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!
        let bindingAID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000003")!
        let bindingBID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000003")!

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

        // Each track owns its own clip with its own per-step lane.
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

        let snapshot = SequencerSnapshotCompiler.compile(project: project)

        let bufferA = try XCTUnwrap(snapshot.clipBuffersByID[clipAID], "ClipA buffer must exist")
        let bufferB = try XCTUnwrap(snapshot.clipBuffersByID[clipBID], "ClipB buffer must exist")

        // ClipA's buffer must carry bindingAID (TrackA's macro) at step 0 → 0.25.
        let overridesA = bufferA.macroOverrides(at: 0)
        XCTAssertEqual(overridesA[bindingAID] ?? -1, 0.25, accuracy: 0.001,
            "ClipA buffer must resolve TrackA's binding (0.25), not TrackB's binding")
        XCTAssertNil(overridesA[bindingBID],
            "ClipA buffer must not contain TrackB's binding ID")

        // ClipB's buffer must carry bindingBID (TrackB's macro) at step 0 → 0.75.
        let overridesB = bufferB.macroOverrides(at: 0)
        XCTAssertEqual(overridesB[bindingBID] ?? -1, 0.75, accuracy: 0.001,
            "ClipB buffer must resolve TrackB's binding (0.75), not TrackA's binding")
        XCTAssertNil(overridesB[bindingAID],
            "ClipB buffer must not contain TrackA's binding ID")
    }
}
