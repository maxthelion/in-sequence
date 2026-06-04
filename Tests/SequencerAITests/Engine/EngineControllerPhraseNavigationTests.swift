import AVFoundation
import XCTest
@testable import SequencerAI

final class EngineControllerPhraseNavigationTests: XCTestCase {
    func test_startInitializesCurrentAndBasisFromSelectedPhrase() throws {
        let fixture = makePhraseNavigationFixture(selectedPhraseIndex: 1)

        startEngineForManualTicks(fixture.controller)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[1].id)

        fixture.controller.stop()
    }

    func test_queueSetsQueuedAndBasisWithoutChangingCurrentOrSnapshotSelection() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.queuedPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[0].id)

        fixture.controller.stop()
    }

    func test_queueReplacementKeepsCurrentPhraseAndUsesLatestQueuedTarget() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[2].id))

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.queuedPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[0].id)

        fixture.controller.stop()
    }

    func test_immediateSwitchClearsQueueAndStartsTargetAtLocalStepZero() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        fixture.controller.processTick(tickIndex: 0, now: 0)
        fixture.sink.reset()
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[2].id))

        XCTAssertTrue(fixture.controller.switchPhraseNow(fixture.phrases[1].id))
        fixture.controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.sink.playedPitches, [72])
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[0].id)

        fixture.controller.stop()
    }

    func test_queuedPhrasePromotesAtCurrentPhraseCycleBoundary() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        fixture.controller.processTick(tickIndex: 0, now: 0)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.queuedPhraseID, fixture.phrases[1].id)

        fixture.controller.processTick(tickIndex: 1, now: 0.1)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)

        fixture.sink.reset()
        fixture.controller.processTick(tickIndex: 2, now: 0.2)
        XCTAssertEqual(fixture.sink.playedPitches, [72])

        fixture.controller.stop()
    }

    func test_stopClearsQueuedPhraseState() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))

        fixture.controller.stop()

        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)
    }

    func test_applyReconcilesInvalidCurrentBasisAndQueuedPhrases() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        XCTAssertTrue(fixture.controller.switchPhraseNow(fixture.phrases[1].id))

        var updatedProject = fixture.project
        updatedProject.removePhrase(id: fixture.phrases[1].id)
        fixture.controller.apply(documentModel: updatedProject)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[2].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)

        fixture.controller.stop()
    }

    func test_startReinitializesFromSnapshotSelectedPhraseAfterStoppedSelectionChange() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.switchPhraseNow(fixture.phrases[1].id))
        fixture.controller.stop()

        var updatedProject = fixture.project
        updatedProject.selectedPhraseID = fixture.phrases[2].id
        fixture.controller.apply(documentModel: updatedProject)
        startEngineForManualTicks(fixture.controller)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[2].id)

        fixture.controller.stop()
    }

    func test_tickFallsBackToSnapshotSelectedPhraseWhenLiveCurrentIsUnset() throws {
        let fixture = makePhraseNavigationFixture(selectedPhraseIndex: 1)

        fixture.controller.processTick(tickIndex: 0, now: 0)

        XCTAssertEqual(fixture.sink.playedPitches, [72])
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
    }

    func test_playbackSnapshotDoesNotCarryPhraseNavigationState() throws {
        let snapshot = SequencerSnapshotCompiler.compile(project: makePhraseNavigationFixture().project)
        let childNames = Set(Mirror(reflecting: snapshot).children.compactMap(\.label))

        XCTAssertFalse(childNames.contains("currentPhraseID"))
        XCTAssertFalse(childNames.contains("queuedPhraseID"))
        XCTAssertFalse(childNames.contains("basisPhraseID"))
        XCTAssertFalse(childNames.contains("phraseCycleStartTick"))
    }
}

private struct PhraseNavigationFixture {
    let controller: EngineController
    let sink: PhraseNavigationAudioSink
    let project: Project
    let phrases: [PhraseModel]
}

private func makePhraseNavigationFixture(selectedPhraseIndex: Int = 0) -> PhraseNavigationFixture {
    let sink = PhraseNavigationAudioSink()
    let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink, stepsPerBar: 2)
    let trackID = UUID(uuidString: "11111111-aaaa-bbbb-cccc-111111111111")!
    let generatorAID = UUID(uuidString: "22222222-aaaa-bbbb-cccc-222222222222")!
    let generatorBID = UUID(uuidString: "33333333-aaaa-bbbb-cccc-333333333333")!
    let generatorCID = UUID(uuidString: "44444444-aaaa-bbbb-cccc-444444444444")!
    let track = StepSequenceTrack(
        id: trackID,
        name: "Phrase Nav Track",
        pitches: [60],
        stepPattern: [true, true],
        stepAccents: [false, false],
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 100,
        gateLength: 1
    )
    let generators = [
        phraseNavigationGenerator(id: generatorAID, name: "A", pattern: [true, true], pitch: 60),
        phraseNavigationGenerator(id: generatorBID, name: "B", pattern: [true, false], pitch: 72),
        phraseNavigationGenerator(id: generatorCID, name: "C", pattern: [true, false], pitch: 84),
    ]
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    let phrases = [
        phraseNavigationPhrase(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!, name: "Phrase A", slotIndex: 0, track: track, layers: layers),
        phraseNavigationPhrase(id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2")!, name: "Phrase B", slotIndex: 1, track: track, layers: layers),
        phraseNavigationPhrase(id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-ccccccccccc3")!, name: "Phrase C", slotIndex: 2, track: track, layers: layers),
    ]
    let patternBank = TrackPatternBank(
        trackID: track.id,
        slots: [
            TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generatorAID)),
            TrackPatternSlot(slotIndex: 1, sourceRef: .generator(generatorBID)),
            TrackPatternSlot(slotIndex: 2, sourceRef: .generator(generatorCID)),
        ]
    )
    let selectedPhraseID = phrases[min(max(0, selectedPhraseIndex), phrases.count - 1)].id
    let project = Project(
        version: 1,
        tracks: [track],
        generatorPool: generators,
        clipPool: [],
        layers: layers,
        routes: [],
        patternBanks: [patternBank],
        selectedTrackID: track.id,
        phrases: phrases,
        selectedPhraseID: selectedPhraseID
    )
    controller.apply(documentModel: project)
    return PhraseNavigationFixture(controller: controller, sink: sink, project: project, phrases: phrases)
}

private func startEngineForManualTicks(_ controller: EngineController) {
    controller.start()
    controller.clock.stop()
}

private func phraseNavigationPhrase(
    id: UUID,
    name: String,
    slotIndex: Int,
    track: StepSequenceTrack,
    layers: [PhraseLayerDefinition]
) -> PhraseModel {
    var phrase = PhraseModel.default(tracks: [track], layers: layers)
    phrase.id = id
    phrase.name = name
    phrase.lengthBars = 1
    phrase.stepsPerBar = 2
    phrase.setPatternIndex(slotIndex, for: track.id, layers: layers)
    return phrase.synced(with: [track], layers: layers)
}

private func phraseNavigationGenerator(
    id: UUID,
    name: String,
    pattern: [Bool],
    pitch: Int
) -> GeneratorPoolEntry {
    GeneratorPoolEntry(
        id: id,
        name: name,
        trackType: .monoMelodic,
        kind: .monoGenerator,
        params: .mono(
            trigger: .native(euclideanAlgo(matching: pattern)),
            pitch: .native(.manual(pitches: [pitch], pickMode: .sequential)),
            shape: NoteShape(velocity: 100, gateLength: 1, accent: false)
        )
    )
}

private final class PhraseNavigationAudioSink: TrackPlaybackSink {
    let displayName = "Phrase Navigation Sink"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth]
    var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit?
    private(set) var playedEvents: [[NoteEvent]] = []

    var playedPitches: [UInt8] {
        playedEvents.flatMap { $0 }.map(\.pitch)
    }

    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() {}
    func shutdown() {}
    func setMix(_ mix: TrackMixSettings) {}
    func setDestination(_ destination: Destination) {}
    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }
    func captureStateBlob() throws -> Data? { nil }
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        playedEvents.append(noteEvents)
    }
    func reset() {
        playedEvents.removeAll()
    }
}
