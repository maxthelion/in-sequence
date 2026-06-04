import XCTest
@testable import SequencerAI

final class TrackFillPreviewEngineTests: XCTestCase {
    func test_clipBackedPreviewShadowsFillAfterResolvedPhraseStep() throws {
        let (project, trackID, _) = makeFillPreviewProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()

        let withoutPreview = EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
        XCTAssertEqual(withoutPreview.map(\.pitch), [60])

        rng = PreviewRNG()
        state = GeneratedSourceEvaluationState()
        let withPreview = EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            trackFillPreview: TrackFillPreviewPlaybackSnapshot(activeTrackID: trackID),
            state: &state,
            rng: &rng
        )

        XCTAssertEqual(withPreview.map(\.pitch), [72])
        XCTAssertEqual(withPreview.map(\.velocity), [118])
    }

    func test_clipBackedPreviewIsIsolatedToActiveTrack() throws {
        let (project, firstTrackID, secondTrackID) = makeTwoTrackFillPreviewProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()

        let firstTrackNotes = EngineController.resolvedStepNotes(
            for: firstTrackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            trackFillPreview: TrackFillPreviewPlaybackSnapshot(activeTrackID: firstTrackID),
            state: &state,
            rng: &rng
        )

        rng = PreviewRNG()
        state = GeneratedSourceEvaluationState()
        let secondTrackNotes = EngineController.resolvedStepNotes(
            for: secondTrackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            trackFillPreview: TrackFillPreviewPlaybackSnapshot(activeTrackID: firstTrackID),
            state: &state,
            rng: &rng
        )

        XCTAssertEqual(firstTrackNotes.map(\.pitch), [72])
        XCTAssertEqual(secondTrackNotes.map(\.pitch), [64])
    }

    func test_generatorBackedResolutionDoesNotConsumeFillPreview() {
        let generatorID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!
        let (project, trackID, _) = makePreviewGeneratorProject(generatorID: generatorID)
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()

        let withoutPreview = EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            state: &state,
            rng: &rng
        )

        rng = PreviewRNG()
        state = GeneratedSourceEvaluationState()
        let withPreview = EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            trackFillPreview: TrackFillPreviewPlaybackSnapshot(activeTrackID: trackID),
            state: &state,
            rng: &rng
        )

        XCTAssertEqual(withPreview, withoutPreview)
    }

    func test_previewCommandInvalidatesPreparedClipStepWithoutPlaybackSnapshotRebuild() {
        let audioSink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let (project, trackID, _) = makeFillPreviewProject()
        controller.apply(documentModel: project)
        let playbackSnapshotApplyCallsBefore = controller.applyPlaybackSnapshotCallCount
        let documentApplyCallsBefore = controller.applyDocumentModelCallCount

        controller.processTick(tickIndex: 0, now: 0)
        XCTAssertFalse(controller.eventQueueIsEmpty, "tick 0 prepares tick 1 before returning")
        audioSink.resetPlayedEvents()

        controller.apply(trackFillPreview: TrackFillPreviewPlaybackSnapshot(activeTrackID: trackID))

        XCTAssertTrue(controller.eventQueueIsEmpty)
        XCTAssertEqual(controller.applyPlaybackSnapshotCallCount, playbackSnapshotApplyCallsBefore)
        XCTAssertEqual(controller.applyDocumentModelCallCount, documentApplyCallsBefore)

        controller.processTick(tickIndex: 1, now: 0.1)

        let playedPitches = audioSink.playedEvents.flatMap { $0 }.map(\.pitch)
        XCTAssertEqual(playedPitches, [72])
    }
}

private func makeFillPreviewProject() -> (Project, UUID, UUID) {
    let trackID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let clipID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let track = previewTrack(id: trackID, name: "Track", pitch: 48)
    let clip = fillPreviewClip(id: clipID, mainPitch: 60, fillPitch: 72)
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [clip])
    let patternBank = TrackPatternBank(trackID: trackID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipID))])
    let project = Project(
        version: 1,
        tracks: [track],
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: [clip],
        layers: layers,
        routes: [],
        patternBanks: [patternBank],
        selectedTrackID: trackID,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
    return (project, trackID, clipID)
}

private func makeTwoTrackFillPreviewProject() -> (Project, UUID, UUID) {
    let firstTrackID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let secondTrackID = UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!
    let firstClipID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let secondClipID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
    let firstTrack = previewTrack(id: firstTrackID, name: "First", pitch: 48)
    let secondTrack = previewTrack(id: secondTrackID, name: "Second", pitch: 50)
    let firstClip = fillPreviewClip(id: firstClipID, mainPitch: 60, fillPitch: 72)
    let secondClip = fillPreviewClip(id: secondClipID, mainPitch: 64, fillPitch: 76)
    let tracks = [firstTrack, secondTrack]
    let clips = [firstClip, secondClip]
    let layers = PhraseLayerDefinition.defaultSet(for: tracks)
    let phrase = PhraseModel.default(tracks: tracks, layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: clips)
    let patternBanks = [
        TrackPatternBank(trackID: firstTrackID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(firstClipID))]),
        TrackPatternBank(trackID: secondTrackID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(secondClipID))]),
    ]
    let project = Project(
        version: 1,
        tracks: tracks,
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: clips,
        layers: layers,
        routes: [],
        patternBanks: patternBanks,
        selectedTrackID: firstTrackID,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
    return (project, firstTrackID, secondTrackID)
}

private func makePreviewGeneratorProject(generatorID: UUID) -> (Project, UUID, UUID) {
    let trackID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let generator = GeneratorPoolEntry.makeDefault(
        id: generatorID,
        name: "Generator",
        kind: .monoGenerator,
        trackType: .monoMelodic
    )
    let track = previewTrack(id: trackID, name: "Generator Track", pitch: 48)
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [])
    let patternBank = TrackPatternBank(trackID: trackID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generatorID))])
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

private func previewTrack(id: UUID, name: String, pitch: Int) -> StepSequenceTrack {
    StepSequenceTrack(
        id: id,
        name: name,
        pitches: [pitch],
        stepPattern: [false],
        stepAccents: [false],
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 70,
        gateLength: 1
    )
}

private func fillPreviewClip(id: UUID, mainPitch: Int, fillPitch: Int) -> ClipPoolEntry {
    ClipPoolEntry(
        id: id,
        name: "Fill Preview",
        trackType: .monoMelodic,
        content: .noteGrid(
            lengthSteps: 1,
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: mainPitch, velocity: 80, lengthSteps: 2)]),
                    fill: ClipLane(chance: 1, notes: [ClipStepNote(pitch: fillPitch, velocity: 118, lengthSteps: 5)])
                )
            ]
        )
    )
}
