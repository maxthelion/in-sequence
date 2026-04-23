import AVFoundation
@testable import SequencerAI

func makeLiveStoreProject(
    clipPitch: Int = 60,
    stepPattern: [Bool] = [true, false],
    macros: [TrackMacroBinding] = []
) -> (Project, UUID, UUID) {
    let trackID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let clipID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let track = StepSequenceTrack(
        id: trackID,
        name: "Track",
        pitches: [48],
        stepPattern: [false, false],
        stepAccents: [false, false],
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 96,
        gateLength: 4,
        macros: macros
    )
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    let phrase = PhraseModel.default(
        tracks: [track],
        layers: layers,
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: []
    )
    let clip = ClipPoolEntry(
        id: clipID,
        name: "Clip",
        trackType: .monoMelodic,
        content: .noteGrid(
            lengthSteps: max(1, stepPattern.count),
            steps: stepPattern.map { isOn in
                guard isOn else {
                    return .empty
                }
                return ClipStep(
                    main: ClipLane(
                        chance: 1,
                        notes: [ClipStepNote(pitch: clipPitch, velocity: 100, lengthSteps: 4)]
                    ),
                    fill: nil
                )
            }
        )
    )
    let patternBank = TrackPatternBank(
        trackID: track.id,
        slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
    )
    let project = Project(
        version: 1,
        tracks: [track],
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: [clip],
        layers: layers,
        routes: [],
        patternBanks: [patternBank],
        selectedTrackID: track.id,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
    return (project, trackID, clipID)
}

final class CountingAudioSink: TrackPlaybackSink {
    let displayName = "Counting"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth]
    private(set) var selectedInstrument = AudioInstrumentChoice.builtInSynth
    var currentAudioUnit: AVAudioUnit?
    private(set) var destinationCallCount = 0
    private(set) var playedEvents: [[NoteEvent]] = []

    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() {}
    func shutdown() {}
    func setMix(_: TrackMixSettings) {}
    func captureStateBlob() throws -> Data? { nil }

    func setDestination(_ destination: Destination) {
        _ = destination
        destinationCallCount += 1
    }

    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }

    func play(noteEvents: [NoteEvent], bpm _: Double, stepsPerBar _: Int) {
        playedEvents.append(noteEvents)
    }

    func resetPlayedEvents() {
        playedEvents.removeAll()
    }
}
