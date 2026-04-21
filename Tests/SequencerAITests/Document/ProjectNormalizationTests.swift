import XCTest
@testable import SequencerAI

final class ProjectNormalizationTests: XCTestCase {
    func test_init_defaults_layers_pattern_banks_and_phrase_when_collections_are_empty() {
        let track = StepSequenceTrack.default
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: [],
            routes: [],
            patternBanks: [],
            selectedTrackID: track.id,
            phrases: [],
            selectedPhraseID: UUID()
        )

        XCTAssertEqual(project.layers.map(\.id), PhraseLayerDefinition.defaultSet(for: [track]).map(\.id))
        XCTAssertEqual(project.patternBanks.count, 1)
        XCTAssertEqual(project.phrases.count, 1)
        XCTAssertEqual(project.selectedTrackID, track.id)
        XCTAssertEqual(project.selectedPhraseID, project.phrases[0].id)
    }

    func test_init_clamps_invalid_selected_ids() {
        let track = StepSequenceTrack.default
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: PhraseLayerDefinition.defaultSet(for: [track]),
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )

        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: PhraseLayerDefinition.defaultSet(for: [track]),
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, initialClipID: nil)],
            selectedTrackID: UUID(),
            phrases: [phrase],
            selectedPhraseID: UUID()
        )

        XCTAssertEqual(project.selectedTrackID, track.id)
        XCTAssertEqual(project.selectedPhraseID, phrase.id)
    }

    func test_decode_filters_or_syncs_pattern_banks_and_phrase_cells_against_current_tracks() throws {
        let track = StepSequenceTrack.default
        let strayTrack = StepSequenceTrack(
            name: "Stray",
            trackType: .monoMelodic,
            pitches: [36],
            stepPattern: Array(repeating: true, count: 16),
            destination: .none,
            velocity: 90,
            gateLength: 2
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track, strayTrack])
        let phrase = PhraseModel(
            id: UUID(),
            name: "Phrase",
            lengthBars: 4,
            stepsPerBar: 16,
            cells: [
                PhraseCellAssignment(trackID: track.id, layerID: "pattern", cell: .single(.index(4))),
                PhraseCellAssignment(trackID: strayTrack.id, layerID: "pattern", cell: .single(.index(9))),
            ]
        )

        let json = """
        {
          "version": 1,
          "tracks": [\(try trackJSON(for: track))],
          "trackGroups": [],
          "generatorPool": \(try generatorPoolJSON()),
          "clipPool": [],
          "layers": \(try jsonString(for: layers)),
          "routes": [],
          "patternBanks": \(try jsonString(for: [
            TrackPatternBank.default(for: track, initialClipID: nil),
            TrackPatternBank.default(for: strayTrack, initialClipID: nil),
          ])),
          "selectedTrackID": "\(track.id.uuidString)",
          "phrases": \(try jsonString(for: [phrase])),
          "selectedPhraseID": "\(phrase.id.uuidString)"
        }
        """

        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))

        XCTAssertEqual(project.patternBanks.map(\.trackID), [track.id])
        XCTAssertEqual(Set(project.phrases[0].cells.map(\.trackID)), [track.id])
        XCTAssertEqual(
            Set(project.phrases[0].cells.map(\.layerID)),
            Set(PhraseLayerDefinition.defaultSet(for: [track]).map(\.id))
        )
    }

    func test_init_filters_pattern_banks_for_tracks_that_do_not_exist() {
        let track = StepSequenceTrack.default
        let strayBank = TrackPatternBank.default(
            for: StepSequenceTrack(
                name: "Stray",
                trackType: .monoMelodic,
                pitches: [48],
                stepPattern: Array(repeating: true, count: 16),
                destination: .none,
                velocity: 96,
                gateLength: 4
            ),
            initialClipID: nil
        )

        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: PhraseLayerDefinition.defaultSet(for: [track]),
            routes: [],
            patternBanks: [
                TrackPatternBank.default(for: track, initialClipID: nil),
                strayBank,
            ],
            selectedTrackID: track.id,
            phrases: [
                PhraseModel.default(
                    tracks: [track],
                    layers: PhraseLayerDefinition.defaultSet(for: [track]),
                    generatorPool: GeneratorPoolEntry.defaultPool,
                    clipPool: []
                )
            ],
            selectedPhraseID: UUID()
        )

        XCTAssertEqual(project.patternBanks.map(\.trackID), [track.id])
    }

    private func generatorPoolJSON() throws -> String {
        try jsonString(for: GeneratorPoolEntry.defaultPool)
    }

    private func trackJSON(for track: StepSequenceTrack) throws -> String {
        try jsonString(for: track)
    }

    private func jsonString<T: Encodable>(for value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to encode JSON string")
            return ""
        }
        return string
    }
}
