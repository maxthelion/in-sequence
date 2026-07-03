import XCTest
@testable import SequencerAI

final class TrackFillPreviewEngineTests: XCTestCase {
    /// Test-isolation convention (bacee620): every controller a test creates
    /// gets a full shutdown at teardown so no TickClock or host work leaks
    /// into later suites.
    private func registerShutdownAtTeardown(_ controller: EngineController) {
        addTeardownBlock {
            controller.shutdown()
            XCTAssertFalse(controller.clock.isRunning,
                "no TickClock may survive test teardown")
        }
    }

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

    /// WS1 AC1: with the phrase fill flag engaged, the realized note stream
    /// for the track equals the clip's FILL items across a full bar (and a
    /// second bar), with the normal (main-lane) items fully absent — asserted
    /// on both the dispatch path (audio sink, per tick) and the event
    /// recorder (per realized step). The clip is a 4-step pattern whose fill
    /// lane carries a DIFFERENT item on every step, so a single lucky step
    /// cannot pass the test (the pre-salvage version was a one-tick smoke
    /// test). Note the model semantic: an empty fill lane normalizes to nil
    /// (`ClipLane.normalized`) and the step falls back to the main lane, so
    /// "fill items only" is asserted through steps that all carry fill items.
    func test_phraseFillFlagPlaysFillLaneThroughDispatchAndRecorder() throws {
        let ticksPerBar = 4
        let audioSink = CountingAudioSink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutput: audioSink,
            stepsPerBar: ticksPerBar
        )
        registerShutdownAtTeardown(controller)
        let (project, trackID) = makeMultiStepFillProject(fillEngaged: true)
        controller.apply(documentModel: project)
        let recorder = controller.enableEventRecording()

        // The clip's lanes, per clip step (see makeMultiStepFillProject):
        // main 60/61/62/63 @80, fill 72/73/74/75 @118.
        let fillPitchesByClipStep: [[Int]] = [[72], [73], [74], [75]]
        let mainPitches = Set(60...63)

        var playedByTick: [[Int]] = []
        for tick in 0..<(2 * ticksPerBar) {
            audioSink.resetPlayedEvents()
            controller.processTick(tickIndex: UInt64(tick), now: Double(tick) * 0.125)
            playedByTick.append(audioSink.playedEvents.flatMap { $0 }.map { Int($0.pitch) }.sorted())
        }

        for tick in 0..<(2 * ticksPerBar) {
            XCTAssertEqual(
                playedByTick[tick],
                fillPitchesByClipStep[tick % ticksPerBar],
                "tick \(tick): with fill engaged the dispatch stream must be exactly the fill lane"
            )
        }

        // Recorder view: every realized event across the bar is a fill item —
        // right pitch for its step, fill velocity, and no main pitch anywhere.
        let blockID = EngineController.generatorBlockID(for: trackID)
        let recorded = recorder.recordedEvents.filter { $0.blockID == blockID }
        XCTAssertFalse(recorded.isEmpty, "the recorder must capture the realized fill stream")
        for event in recorded {
            let expected = fillPitchesByClipStep[event.step % ticksPerBar]
            XCTAssertEqual([Int(event.pitch)], expected,
                           "step \(event.step): recorded pitch must be the fill item")
            XCTAssertEqual(Int(event.velocity), 118,
                           "step \(event.step): recorded velocity must be the fill item's")
            XCTAssertFalse(mainPitches.contains(Int(event.pitch)),
                           "step \(event.step): no normal (main-lane) item may be realized")
        }
        let recordedSteps = Set(recorded.map { $0.step % ticksPerBar })
        XCTAssertEqual(recordedSteps, [0, 1, 2, 3],
                       "every fill step of the bar must be realized")
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

/// A 4-step clip-backed project with the phrase fill flag optionally engaged
/// for the track. Main lane: 60/61/62/63 @80. Fill lane: 72/73/74/75 @118 —
/// a distinct fill item on every step, so a realized-stream comparison across
/// a full bar distinguishes the lanes at every position.
private func makeMultiStepFillProject(fillEngaged: Bool) -> (Project, UUID) {
    let trackID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let clipID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let track = previewTrack(id: trackID, name: "Track", pitch: 48)
    let clip = ClipPoolEntry(
        id: clipID,
        name: "Multi-Step Fill",
        trackType: .monoMelodic,
        content: .noteGrid(
            lengthSteps: 4,
            steps: (0..<4).map { stepIndex in
                ClipStep(
                    main: ClipLane(
                        chance: 1,
                        notes: [ClipStepNote(pitch: 60 + stepIndex, velocity: 80, lengthSteps: 2)]
                    ),
                    fill: ClipLane(
                        chance: 1,
                        notes: [ClipStepNote(pitch: 72 + stepIndex, velocity: 118, lengthSteps: 2)]
                    )
                )
            }
        )
    )
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    var phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [clip])
    if fillEngaged,
       let fillLayer = layers.first(where: { $0.target == .macroRow("fill-flag") }) {
        phrase.setCell(.single(.bool(true)), for: fillLayer.id, trackID: trackID)
    }
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
    return (project, trackID)
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
