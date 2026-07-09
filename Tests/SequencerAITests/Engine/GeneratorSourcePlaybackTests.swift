import XCTest
@testable import SequencerAI

final class GeneratorSourcePlaybackTests: XCTestCase {
    func test_generatorSourcePlayback_appliesOwnPitchStageWithoutModifier() throws {
        let generator = Self.generator(
            triggerPitch: 60,
            pitch: .manual(pitches: [72], pickMode: .sequential)
        )
        let snapshot = Self.snapshot(generator: generator, sourceRef: SourceRef(
            mode: .generator,
            generatorID: generator.id,
            modifierGeneratorID: nil
        ))

        let notes = Self.resolvedNotes(snapshot: snapshot)

        XCTAssertEqual(notes.map(\.pitch), [72])
    }

    func test_generatorSourcePlayback_matchesDeterministicPreview() throws {
        let generator = Self.generator(
            triggerPitch: 60,
            pitch: .randomInChord(root: 60, chord: .majorTriad, inverted: false, spread: 12),
            harmonicSidechain: .projectChordContext
        )
        let snapshot = Self.snapshot(generator: generator, sourceRef: SourceRef(
            mode: .generator,
            generatorID: generator.id,
            modifierGeneratorID: nil
        ))
        let chordContext = Chord(root: 65, chordType: ChordID.minorTriad.rawValue, scale: ScaleID.dorian.rawValue)

        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        let playback = (0..<4).map { step in
            EngineController.resolvedStepNotes(
                for: snapshot.trackID,
                in: snapshot.snapshot,
                phraseID: snapshot.snapshot.selectedPhraseID,
                stepIndex: step,
                chordContext: chordContext,
                state: &state,
                rng: &rng
            )
        }
        let preview = GeneratedSourceEvaluator.previewNotes(
            for: generator.params,
            clipChoices: [],
            count: 4,
            chordContext: chordContext
        )

        XCTAssertEqual(playback, preview)
    }

    func test_generatorSourcePlayback_legacySelfModifierDoesNotDoubleProcess() throws {
        let generator = Self.generator(
            triggerPitch: 60,
            pitch: .manual(pitches: [72], pickMode: .sequential)
        )
        let snapshot = Self.snapshot(generator: generator, sourceRef: .generator(generator.id))

        let notes = Self.resolvedNotes(snapshot: snapshot)

        XCTAssertEqual(notes.map(\.pitch), [72])
    }

    func test_generatorSourcePlayback_modifierBypassDoesNotBypassSourcePitch() throws {
        let generator = Self.generator(
            triggerPitch: 60,
            pitch: .manual(pitches: [72], pickMode: .sequential)
        )
        let modifier = Self.generator(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            name: "Modifier",
            triggerPitch: 60,
            pitch: .manual(pitches: [48], pickMode: .sequential)
        )
        let snapshot = Self.snapshot(
            generator: generator,
            extraGenerators: [modifier],
            sourceRef: SourceRef(
                mode: .generator,
                generatorID: generator.id,
                modifierGeneratorID: modifier.id,
                modifierBypassed: true
            )
        )

        let notes = Self.resolvedNotes(snapshot: snapshot)

        XCTAssertEqual(notes.map(\.pitch), [72])
    }

    func test_generatorSourcePlayback_sourceAndModifierKeepSeparateStateScopes() throws {
        let source = Self.generator(
            triggerPitch: 60,
            pitch: .manual(pitches: [72], pickMode: .sequential)
        )
        let modifier = Self.generator(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            name: "Modifier",
            triggerPitch: 60,
            pitch: .manual(pitches: [48], pickMode: .sequential)
        )
        let snapshot = Self.snapshot(
            generator: source,
            extraGenerators: [modifier],
            sourceRef: SourceRef(
                mode: .generator,
                generatorID: source.id,
                modifierGeneratorID: modifier.id,
                modifierBypassed: false
            )
        )
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()

        let notes = EngineController.resolvedStepNotes(
            for: snapshot.trackID,
            in: snapshot.snapshot,
            phraseID: snapshot.snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            state: &state,
            rng: &rng
        )

        XCTAssertEqual(notes.map(\.pitch), [48])
        XCTAssertEqual(
            state.scopedLastPitchesByLane[.generatorSource(slotIndex: 0, generatorID: source.id)]?.first ?? nil,
            72
        )
        XCTAssertEqual(
            state.scopedLastPitchesByLane[.generatorModifier(slotIndex: 0, generatorID: modifier.id)]?.first ?? nil,
            48
        )
        XCTAssertEqual(state.lastPitchesByLane.first ?? nil, 72)
    }

    func test_generatorSourcePlayback_sameGeneratorInDifferentSlotsKeepsSeparateStateScopes() throws {
        let generator = Self.generator(
            triggerPitch: 60,
            pitch: .manual(pitches: [72], pickMode: .sequential)
        )
        let snapshot = Self.snapshot(
            generator: generator,
            sourceRef: SourceRef(mode: .generator, generatorID: generator.id),
            extraSlots: [
                TrackPatternSlot(
                    slotIndex: 1,
                    sourceRef: SourceRef(mode: .generator, generatorID: generator.id)
                )
            ]
        )
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()

        _ = EngineController.resolvedStepNotes(
            for: snapshot.trackID,
            in: snapshot.snapshot,
            phraseID: snapshot.snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            quantisedPatternSlotOverrides: [snapshot.trackID: 0],
            state: &state,
            rng: &rng
        )
        _ = EngineController.resolvedStepNotes(
            for: snapshot.trackID,
            in: snapshot.snapshot,
            phraseID: snapshot.snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            quantisedPatternSlotOverrides: [snapshot.trackID: 1],
            state: &state,
            rng: &rng
        )

        XCTAssertNotNil(
            state.scopedLastPitchesByLane[.generatorSource(slotIndex: 0, generatorID: generator.id)]
        )
        XCTAssertNotNil(
            state.scopedLastPitchesByLane[.generatorSource(slotIndex: 1, generatorID: generator.id)]
        )
    }

    func test_clipSourcePlayback_stillUsesClipNotesWithoutModifier() throws {
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            name: "Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(main: ClipLane(chance: 1, notes: [
                    ClipStepNote(pitch: 55, velocity: 90, lengthSteps: 2)
                ]), fill: nil)]
            )
        )
        let snapshot = Self.snapshot(
            generator: Self.generator(),
            clips: [clip],
            sourceRef: SourceRef(mode: .clip, clipID: clip.id)
        )

        let notes = Self.resolvedNotes(snapshot: snapshot)

        XCTAssertEqual(notes.map(\.pitch), [55])
        XCTAssertEqual(notes.map(\.velocity), [90])
        XCTAssertEqual(notes.map(\.length), [2])
    }

    private static func generator(
        id: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        name: String = "Generator",
        triggerPitch: Int = 60,
        pitch: PitchAlgo = .manual(pitches: [72], pickMode: .sequential),
        harmonicSidechain: HarmonicSidechainSource = .none
    ) -> GeneratorPoolEntry {
        GeneratorPoolEntry(
            id: id,
            name: name,
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0), basePitch: triggerPitch),
                pitch: .native(pitch, harmonicSidechain: harmonicSidechain),
                shape: NoteShape(velocity: 96, gateLength: 4, accent: false)
            )
        )
    }

    private static func snapshot(
        generator: GeneratorPoolEntry,
        extraGenerators: [GeneratorPoolEntry] = [],
        clips: [ClipPoolEntry] = [],
        sourceRef: SourceRef,
        extraSlots: [TrackPatternSlot] = []
    ) -> (snapshot: PlaybackSnapshot, trackID: UUID) {
        let trackID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
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
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: [generator] + extraGenerators,
            clipPool: clips
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator] + extraGenerators,
            clipPool: clips,
            layers: layers,
            routes: [],
            patternBanks: [
                TrackPatternBank(trackID: trackID, slots: [
                    TrackPatternSlot(slotIndex: 0, sourceRef: sourceRef)
                ] + extraSlots)
            ],
            selectedTrackID: trackID,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (SequencerSnapshotCompiler.compile(project: project), trackID)
    }

    private static func resolvedNotes(snapshot fixture: (snapshot: PlaybackSnapshot, trackID: UUID)) -> [GeneratedNote] {
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        return EngineController.resolvedStepNotes(
            for: fixture.trackID,
            in: fixture.snapshot,
            phraseID: fixture.snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
    }
}
