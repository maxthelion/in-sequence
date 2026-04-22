import XCTest
@testable import SequencerAI

final class SequencerSnapshotCompilerTests: XCTestCase {
    func test_compiles_clip_buffers_phrase_steps_and_macro_overrides() throws {
        let fixture = makeSnapshotFixture()
        let snapshot = SequencerSnapshotCompiler.compile(project: fixture.project)

        let clipBuffer = try XCTUnwrap(snapshot.clipBuffersByID[fixture.clip.id])
        XCTAssertEqual(clipBuffer.lengthSteps, 2)
        XCTAssertEqual(clipBuffer.steps[0].main?.notes.first?.pitch, 60)
        XCTAssertEqual(clipBuffer.steps[1].main?.notes.first?.pitch, 62)
        XCTAssertEqual(clipBuffer.macroOverride(stepIndex: 0, bindingID: fixture.binding.id), 0.8)
        XCTAssertNil(clipBuffer.macroOverride(stepIndex: 1, bindingID: fixture.binding.id))

        let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffersByID[fixture.phrase.id])
        let trackBuffer = try XCTUnwrap(phraseBuffer.trackStates.first)
        XCTAssertEqual(trackBuffer.patternSlotIndex, [0, 3])
        XCTAssertEqual(trackBuffer.macroValues[0], [0.25])
        XCTAssertEqual(trackBuffer.macroValues[1], [0.5])
    }

    @MainActor
    func test_compiles_from_live_store_resident_state() throws {
        let fixture = makeSnapshotFixture()
        let store = LiveSequencerStore(project: fixture.project)

        store.updateClipContent(
            id: fixture.clip.id,
            content: .stepSequence(stepPattern: [true, false], pitches: [72, 74])
        )
        store.setPhraseCell(
            .steps([.index(4), .index(5)]),
            layerID: fixture.patternLayer.id,
            trackIDs: [fixture.track.id],
            phraseID: fixture.phrase.id
        )

        let snapshot = SequencerSnapshotCompiler.compile(store: store)

        let clipBuffer = try XCTUnwrap(snapshot.clipBuffersByID[fixture.clip.id])
        XCTAssertEqual(clipBuffer.steps[0].main?.notes.first?.pitch, 72)
        XCTAssertNil(clipBuffer.steps[1].main)

        let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffersByID[fixture.phrase.id])
        let trackBuffer = try XCTUnwrap(phraseBuffer.trackStates.first)
        XCTAssertEqual(trackBuffer.patternSlotIndex, [4, 5])
    }

    private func makeSnapshotFixture() -> (
        project: Project,
        track: StepSequenceTrack,
        clip: ClipPoolEntry,
        phrase: PhraseModel,
        binding: TrackMacroBinding,
        patternLayer: PhraseLayerDefinition
    ) {
        let trackID = UUID()
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Gain",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.1,
            valueType: .scalar,
            source: .builtin(.sampleGain)
        )
        let binding = TrackMacroBinding(descriptor: descriptor)
        let track = StepSequenceTrack(
            id: trackID,
            name: "Track",
            trackType: .monoMelodic,
            pitches: [60, 62],
            stepPattern: [true, true],
            velocity: 100,
            gateLength: 4,
            macros: [binding]
        )
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Clip",
            trackType: track.trackType,
            content: .stepSequence(stepPattern: [true, true], pitches: [60, 62]),
            macroLanes: [binding.id: MacroLane(values: [0.8, nil])]
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let patternLayer = layers.first(where: { $0.target == .patternIndex })!
        let macroLayerID = "macro-\(track.id.uuidString)-\(binding.id.uuidString)"
        let phrase = PhraseModel(
            id: UUID(),
            name: "Phrase",
            lengthBars: 1,
            stepsPerBar: 2,
            cells: [
                PhraseCellAssignment(trackID: track.id, layerID: patternLayer.id, cell: .steps([.index(0), .index(3)])),
                PhraseCellAssignment(trackID: track.id, layerID: macroLayerID, cell: .steps([.scalar(0.25), .scalar(0.5)]))
            ] + layers
                .filter { $0.id != patternLayer.id && $0.id != macroLayerID }
                .map { PhraseCellAssignment(trackID: track.id, layerID: $0.id, cell: .inheritDefault) }
        )
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: (0..<TrackPatternBank.slotCount).map {
                TrackPatternSlot(slotIndex: $0, sourceRef: .clip($0 == 0 ? clip.id : nil))
            }
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            patternBanks: [bank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, track, clip, phrase, binding, patternLayer)
    }
}
