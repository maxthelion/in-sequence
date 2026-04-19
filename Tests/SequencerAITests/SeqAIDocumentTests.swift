import XCTest
@testable import SequencerAI

final class SeqAIDocumentModelTests: XCTestCase {
    func test_empty_uses_project_scoped_layers() {
        let model = SeqAIDocumentModel.empty

        XCTAssertEqual(model.layers.map(\.id), [
            "pattern",
            "mute",
            "volume",
            "transpose",
            "intensity",
            "density",
            "tension",
            "register",
            "variance",
            "brightness",
            "fill-flag",
            "swing",
        ])
        XCTAssertEqual(model.phrases.count, 1)
        XCTAssertEqual(model.selectedPatternIndex(for: model.selectedTrack.id), 0)
        XCTAssertEqual(model.selectedPhrase.cell(for: "pattern", trackID: model.selectedTrack.id), .inheritDefault)
    }

    func test_layer_editor_kinds_expose_expected_modes() throws {
        let track = StepSequenceTrack.default
        let layers = PhraseLayerDefinition.defaultSet(for: [track])

        let pattern = try XCTUnwrap(layers.first(where: { $0.id == "pattern" }))
        let mute = try XCTUnwrap(layers.first(where: { $0.id == "mute" }))
        let intensity = try XCTUnwrap(layers.first(where: { $0.id == "intensity" }))

        XCTAssertEqual(pattern.editorKind, .indexedChoice)
        XCTAssertEqual(pattern.availableModes, [.inheritDefault, .single, .bars])

        XCTAssertEqual(mute.editorKind, .toggleBoolean)
        XCTAssertEqual(mute.availableModes, [.inheritDefault, .single, .bars])

        XCTAssertEqual(intensity.editorKind, .continuousScalar)
        XCTAssertEqual(intensity.availableModes, [.inheritDefault, .single, .bars, .steps, .curve])
    }

    func test_set_selected_pattern_index_writes_pattern_layer_cell() {
        var model = SeqAIDocumentModel.empty

        model.setSelectedPatternIndex(7, for: model.selectedTrack.id)

        XCTAssertEqual(model.selectedPatternIndex(for: model.selectedTrack.id), 7)
        XCTAssertEqual(model.selectedPhrase.cell(for: "pattern", trackID: model.selectedTrack.id), .single(.index(7)))
    }

    func test_append_track_syncs_layer_defaults_and_phrase_cells() {
        var model = SeqAIDocumentModel.empty

        model.appendTrack(trackType: .polyMelodic)

        let newTrack = model.selectedTrack

        XCTAssertEqual(model.tracks.count, 2)
        XCTAssertEqual(model.layers.count, 12)
        XCTAssertEqual(model.selectedPhrase.cell(for: "pattern", trackID: newTrack.id), .inheritDefault)
        XCTAssertEqual(model.layers.first(where: { $0.id == "pattern" })?.defaultValue(for: newTrack.id), .index(0))
        XCTAssertEqual(model.layers.first(where: { $0.id == "volume" })?.defaultValue(for: newTrack.id), .scalar(newTrack.mix.level * 127))
    }

    func test_phrase_sync_removes_missing_tracks_and_layers() {
        let track = StepSequenceTrack.default
        let otherTrack = StepSequenceTrack(
            name: "Other",
            pitches: [48],
            stepPattern: Array(repeating: true, count: 16),
            velocity: 90,
            gateLength: 2
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track, otherTrack])
        let phrase = PhraseModel(
            id: UUID(),
            name: "Phrase X",
            lengthBars: 4,
            stepsPerBar: 16,
            cells: [
                PhraseCellAssignment(trackID: track.id, layerID: "pattern", cell: .single(.index(2))),
                PhraseCellAssignment(trackID: otherTrack.id, layerID: "pattern", cell: .single(.index(9))),
                PhraseCellAssignment(trackID: otherTrack.id, layerID: "ghost-layer", cell: .single(.scalar(1))),
            ]
        )

        let synced = phrase.synced(with: [track], layers: Array(layers.prefix(1)))

        XCTAssertEqual(synced.cells.count, 1)
        XCTAssertEqual(synced.patternIndex(for: track.id, layers: Array(layers.prefix(1))), 2)
    }

    func test_phrase_resolves_scalar_modes() {
        let track = StepSequenceTrack.default
        let layer = PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "intensity" })!
        var phrase = PhraseModel.default(tracks: [track], layers: [layer])

        phrase.setCell(.bars([.scalar(0.1), .scalar(0.8)]), for: layer.id, trackID: track.id)
        XCTAssertEqual(phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0), .scalar(0.1))
        XCTAssertEqual(phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 16), .scalar(0.8))

        phrase.setCell(.curve([0.0, 1.0]), for: layer.id, trackID: track.id)
        let sampled = phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: phrase.stepCount - 1)
        XCTAssertEqual(sampled, .scalar(1.0))
    }

    func test_add_drum_kit_creates_group_and_inherit_cells() throws {
        var model = SeqAIDocumentModel.empty

        let groupID = try XCTUnwrap(model.addDrumKit(.kit808))

        XCTAssertEqual(model.trackGroups.count, 1)
        XCTAssertEqual(model.trackGroups[0].id, groupID)
        XCTAssertEqual(model.trackGroups[0].memberIDs.count, DrumKitPreset.kit808.members.count)
        XCTAssertTrue(model.tracks.suffix(DrumKitPreset.kit808.members.count).allSatisfy { $0.destination == .inheritGroup })
        XCTAssertTrue(model.phrases.allSatisfy { phrase in
            model.trackGroups[0].memberIDs.allSatisfy { memberID in
                phrase.cell(for: "pattern", trackID: memberID) == .inheritDefault
            }
        })
    }

    func test_codable_roundtrip_preserves_layers_and_cells() throws {
        let track = StepSequenceTrack.default
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phraseID = UUID()
        let model = SeqAIDocumentModel(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [])],
            selectedTrackID: track.id,
            phrases: [
                PhraseModel(
                    id: phraseID,
                    name: "Verse",
                    lengthBars: 4,
                    stepsPerBar: 16,
                    cells: [
                        PhraseCellAssignment(trackID: track.id, layerID: "pattern", cell: .single(.index(3))),
                        PhraseCellAssignment(trackID: track.id, layerID: "mute", cell: .single(.bool(true))),
                    ]
                )
            ],
            selectedPhraseID: phraseID
        )

        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: data)

        XCTAssertEqual(decoded.layers, model.layers)
        XCTAssertEqual(decoded.selectedPhrase.cells, model.selectedPhrase.cells)
        XCTAssertEqual(decoded.selectedPatternIndex(for: track.id), 3)
    }
}
