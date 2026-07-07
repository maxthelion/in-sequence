import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class GeneratorBakeSessionTests: XCTestCase {
    private final class DocumentBox {
        var document: SeqAIDocument

        init(project: Project) {
            self.document = SeqAIDocument(project: project)
        }
    }

    func test_bakeGeneratorToClip_createsPlayableClipAndRetainsGeneratorRecipe() throws {
        let generator = Self.generator(pitch: 72)
        let (session, _) = Self.session(generator: generator, sourceRef: .generator(generator.id))
        let trackID = session.store.selectedTrackID

        let bakedClipID = try XCTUnwrap(session.bakeGeneratorToClip(trackID: trackID, slotIndex: 0))
        let bakedSlot = session.store.patternBank(for: trackID).slot(at: 0)

        XCTAssertEqual(bakedSlot.sourceRef.mode, .clip)
        XCTAssertEqual(bakedSlot.sourceRef.clipID, bakedClipID)
        XCTAssertEqual(bakedSlot.sourceRef.generatorID, generator.id)
        XCTAssertNil(bakedSlot.sourceRef.modifierGeneratorID)
        XCTAssertEqual(session.store.generatorEntry(id: generator.id)?.params, generator.params)

        let bakedNotes = Self.resolvedNotes(session: session, trackID: trackID)
        XCTAssertEqual(bakedNotes.map(\.pitch), [72])

        session.setPatternSourceRef(
            SourceRef(mode: .generator, generatorID: generator.id, clipID: bakedClipID),
            for: trackID,
            slotIndex: 0
        )

        let liveGeneratorNotes = Self.resolvedNotes(session: session, trackID: trackID)
        XCTAssertEqual(liveGeneratorNotes.map(\.pitch), [72])
    }

    func test_bakeGeneratorToClip_preservesBypassedSeparateModifierWhenItDidNotShapeTheBake() throws {
        let source = Self.generator(pitch: 72)
        let modifier = Self.generator(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            name: "Separate Modifier",
            pitch: 55
        )
        let (session, _) = Self.session(
            generator: source,
            extraGenerators: [modifier],
            sourceRef: SourceRef(
                mode: .generator,
                generatorID: source.id,
                modifierGeneratorID: modifier.id,
                modifierBypassed: true
            )
        )
        let trackID = session.store.selectedTrackID

        let bakedClipID = try XCTUnwrap(session.bakeGeneratorToClip(trackID: trackID, slotIndex: 0))
        let bakedSlot = session.store.patternBank(for: trackID).slot(at: 0)

        XCTAssertEqual(bakedSlot.sourceRef.mode, .clip)
        XCTAssertEqual(bakedSlot.sourceRef.clipID, bakedClipID)
        XCTAssertEqual(bakedSlot.sourceRef.generatorID, source.id)
        XCTAssertEqual(bakedSlot.sourceRef.modifierGeneratorID, modifier.id)
        XCTAssertTrue(bakedSlot.sourceRef.modifierBypassed)
    }

    func test_bakeGeneratorToClip_freezesActiveSeparateModifierAndDoesNotKeepItLive() throws {
        let source = Self.generator(pitch: 72)
        let modifier = Self.generator(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            name: "Separate Modifier",
            pitch: 55
        )
        let (session, _) = Self.session(
            generator: source,
            extraGenerators: [modifier],
            sourceRef: SourceRef(
                mode: .generator,
                generatorID: source.id,
                modifierGeneratorID: modifier.id,
                modifierBypassed: false
            )
        )
        let trackID = session.store.selectedTrackID

        let bakedClipID = try XCTUnwrap(session.bakeGeneratorToClip(trackID: trackID, slotIndex: 0))
        let bakedSlot = session.store.patternBank(for: trackID).slot(at: 0)

        XCTAssertEqual(bakedSlot.sourceRef.mode, .clip)
        XCTAssertEqual(bakedSlot.sourceRef.clipID, bakedClipID)
        XCTAssertEqual(bakedSlot.sourceRef.generatorID, source.id)
        XCTAssertNil(bakedSlot.sourceRef.modifierGeneratorID)
        XCTAssertFalse(bakedSlot.sourceRef.modifierBypassed)
        XCTAssertEqual(Self.resolvedNotes(session: session, trackID: trackID).map(\.pitch), [55])
    }

    func test_bakeGeneratorToClip_returnsNilWhenRetainedGeneratorIsNotTheActiveSource() throws {
        let generator = Self.generator(pitch: 72)
        let (session, _) = Self.session(
            generator: generator,
            sourceRef: SourceRef(mode: .clip, generatorID: generator.id, clipID: nil)
        )
        let trackID = session.store.selectedTrackID

        XCTAssertNil(session.bakeGeneratorToClip(trackID: trackID, slotIndex: 0))

        let slot = session.store.patternBank(for: trackID).slot(at: 0)
        XCTAssertEqual(slot.sourceRef.mode, .clip)
        XCTAssertEqual(slot.sourceRef.generatorID, generator.id)
        XCTAssertTrue(session.store.clipPool.isEmpty)
    }

    func test_bakeGeneratorToClip_usesLiveChordContextResolutionPath() throws {
        let generator = Self.generator(
            pitch: .randomInChord(root: 60, chord: .majorTriad, inverted: false, spread: 12),
            harmonicSidechain: .projectChordContext
        )
        let chordContext = Chord(root: 65, chordType: ChordID.minorTriad.rawValue, scale: ScaleID.dorian.rawValue)
        let (session, _) = Self.session(generator: generator, sourceRef: .generator(generator.id))
        let trackID = session.store.selectedTrackID
        let liveNotes = Self.resolvedNotes(
            session: session,
            trackID: trackID,
            chordContext: chordContext
        )

        _ = try XCTUnwrap(session.bakeGeneratorToClip(
            trackID: trackID,
            slotIndex: 0,
            chordContext: chordContext
        ))

        let bakedNotes = Self.resolvedNotes(session: session, trackID: trackID)
        XCTAssertEqual(bakedNotes, liveNotes)
    }

    func test_randomizeAfterBakeChangesAudiblePlaybackWhenBakedSlotIsSelected() throws {
        let generator = Self.generator(pitch: 72)
        let (session, _) = Self.session(generator: generator, sourceRef: .generator(generator.id))
        let trackID = session.store.selectedTrackID

        let bakedClipID = try XCTUnwrap(session.bakeGeneratorToClip(trackID: trackID, slotIndex: 0))
        XCTAssertEqual(Self.resolvedNotes(session: session, trackID: trackID).map(\.pitch), [72])

        let randomizedClipID = session.bakeRandomizedClip(
            at: PatternSlotAddress(trackID: trackID, slotIndex: 0),
            settings: ClipRandomizeSettings(density: 0),
            seed: 123
        )

        XCTAssertEqual(randomizedClipID, bakedClipID)
        XCTAssertTrue(Self.resolvedNotes(session: session, trackID: trackID).isEmpty)
    }

    func test_randomizeAfterBakeDoesNotChangePlaybackWhenPatternSelectsAnotherSlot() throws {
        let generator = Self.generator(pitch: 72)
        let (session, _) = Self.session(generator: generator, sourceRef: .generator(generator.id))
        let trackID = session.store.selectedTrackID
        let slotOneClipID = try XCTUnwrap(session.createBlankClipSource(trackID: trackID, slotIndex: 1))
        session.mutateClip(id: slotOneClipID) { entry in
            entry.content = .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(
                            chance: 1,
                            notes: [ClipStepNote(pitch: 55, velocity: 96, lengthSteps: 4)]
                        ),
                        fill: nil
                    )
                ]
            )
        }

        _ = try XCTUnwrap(session.bakeGeneratorToClip(trackID: trackID, slotIndex: 0))
        _ = session.bakeRandomizedClip(
            at: PatternSlotAddress(trackID: trackID, slotIndex: 0),
            settings: ClipRandomizeSettings(density: 0),
            seed: 123
        )

        session.setPhraseCell(
            .single(.index(1)),
            layerID: "pattern",
            trackIDs: [trackID],
            phraseID: session.store.selectedPhraseID
        )

        let slotOneNotes = Self.resolvedNotes(session: session, trackID: trackID)
        XCTAssertEqual(slotOneNotes.map(\.pitch), [55])
    }

    private static func generator(
        id: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        name: String = "Generator",
        pitch: Int
    ) -> GeneratorPoolEntry {
        generator(
            id: id,
            name: name,
            pitch: .manual(pitches: [pitch], pickMode: .sequential),
            harmonicSidechain: .none
        )
    }

    private static func generator(
        id: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        name: String = "Generator",
        pitch: PitchAlgo,
        harmonicSidechain: HarmonicSidechainSource = .none
    ) -> GeneratorPoolEntry {
        GeneratorPoolEntry(
            id: id,
            name: name,
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0), basePitch: 60),
                pitch: .native(pitch, harmonicSidechain: harmonicSidechain),
                shape: NoteShape(velocity: 96, gateLength: 4, accent: false)
            )
        )
    }

    private static func session(
        generator: GeneratorPoolEntry,
        extraGenerators: [GeneratorPoolEntry] = [],
        sourceRef: SourceRef
    ) -> (SequencerDocumentSession, DocumentBox) {
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
        let generators = [generator] + extraGenerators
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: generators,
            clipPool: []
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [
                TrackPatternBank(trackID: trackID, slots: [
                    TrackPatternSlot(slotIndex: 0, sourceRef: sourceRef)
                ])
            ],
            selectedTrackID: trackID,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        let box = DocumentBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        return (session, box)
    }

    private static func resolvedNotes(
        session: SequencerDocumentSession,
        trackID: UUID,
        stepIndex: Int = 0,
        chordContext: Chord? = nil,
        patternSlotOverrides: [UUID: Int] = [:]
    ) -> [GeneratedNote] {
        let snapshot = SequencerSnapshotCompiler.compile(state: session.store.compileInput())
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        return EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: stepIndex,
            chordContext: chordContext,
            quantisedPatternSlotOverrides: patternSlotOverrides,
            state: &state,
            rng: &rng
        )
    }
}
