import XCTest
@testable import SequencerAI

final class EngineControllerMixerBusTests: XCTestCase {
    func test_effectiveMute_usesAuthoredMuteWhenNoSoloIsActive() {
        var project = Self.project()
        project.tracks[0].mix.isMuted = true
        project.buses[0].mix.isMuted = true

        let state = EngineController.effectiveMixerMuteState(for: project)

        XCTAssertFalse(state.isSoloActive)
        XCTAssertEqual(state.mutedTrackIDs, [project.tracks[0].id])
        XCTAssertEqual(state.mutedBusIDs, [project.buses[0].id])
    }

    func test_effectiveMute_soloedBusAudiblyCarriesRoutedTracksAndMutesDirectMasterTracks() {
        var project = Self.project()
        project.buses[0].mix.isSoloed = true

        let state = EngineController.effectiveMixerMuteState(for: project)

        XCTAssertTrue(state.isSoloActive)
        XCTAssertFalse(state.mutedTrackIDs.contains(project.tracks[0].id))
        XCTAssertTrue(state.mutedTrackIDs.contains(project.tracks[1].id))
        XCTAssertFalse(state.mutedBusIDs.contains(project.buses[0].id))
        XCTAssertTrue(state.mutedBusIDs.contains(project.buses[1].id))
    }

    func test_effectiveMute_soloedTrackKeepsItsBusPathOpenWithoutPersistingMembership() {
        var project = Self.project()
        project.tracks[0].mix.isSoloed = true

        let state = EngineController.effectiveMixerMuteState(for: project)

        XCTAssertTrue(state.isSoloActive)
        XCTAssertFalse(state.mutedTrackIDs.contains(project.tracks[0].id))
        XCTAssertTrue(state.mutedTrackIDs.contains(project.tracks[1].id))
        XCTAssertFalse(state.mutedBusIDs.contains(project.buses[0].id))
        XCTAssertTrue(state.mutedBusIDs.contains(project.buses[1].id))
        XCTAssertTrue(project.buses.allSatisfy { !$0.mix.isSoloed })
    }

    func test_effectiveMute_clearSoloFallsBackToAuthoredMuteOnly() {
        var project = Self.project()
        project.tracks[0].mix.isSoloed = true
        project.buses[1].mix.isSoloed = true

        project.clearAllSolo()
        let state = EngineController.effectiveMixerMuteState(for: project)

        XCTAssertFalse(state.isSoloActive)
        XCTAssertTrue(state.mutedTrackIDs.isEmpty)
        XCTAssertTrue(state.mutedBusIDs.isEmpty)
        XCTAssertFalse(project.tracks.contains { $0.mix.isSoloed })
        XCTAssertFalse(project.buses.contains { $0.mix.isSoloed })
    }

    private static func project() -> Project {
        let busA = MixerBus(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!, name: "Drums")
        let busB = MixerBus(id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!, name: "FX")
        let routedTrack = StepSequenceTrack(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Kick",
            trackType: .slice,
            pitches: [36],
            stepPattern: [true],
            destination: .sample(sampleID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, settings: .default),
            outputBusID: busA.id,
            velocity: 100,
            gateLength: 4
        )
        let directTrack = StepSequenceTrack(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Lead",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [routedTrack, directTrack])
        let phrase = PhraseModel.default(
            tracks: [routedTrack, directTrack],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        return Project(
            version: 1,
            tracks: [routedTrack, directTrack],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            buses: [busA, busB],
            patternBanks: [
                TrackPatternBank.default(for: routedTrack, initialClipID: nil),
                TrackPatternBank.default(for: directTrack, initialClipID: nil),
            ],
            selectedTrackID: routedTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }
}
