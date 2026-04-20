import XCTest
@testable import SequencerAI

final class ProjectTests: XCTestCase {
    func test_empty_uses_project_scoped_layers() {
        let model = Project.empty

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
        var model = Project.empty

        model.setSelectedPatternIndex(7, for: model.selectedTrack.id)

        XCTAssertEqual(model.selectedPatternIndex(for: model.selectedTrack.id), 7)
        XCTAssertEqual(model.selectedPhrase.cell(for: "pattern", trackID: model.selectedTrack.id), .single(.index(7)))
    }

    func test_append_track_syncs_layer_defaults_and_phrase_cells() {
        var model = Project.empty

        model.appendTrack(trackType: .polyMelodic)

        let newTrack = model.selectedTrack

        XCTAssertEqual(model.tracks.count, 2)
        XCTAssertEqual(model.layers.count, 12)
        XCTAssertEqual(model.selectedPhrase.cell(for: "pattern", trackID: newTrack.id), .inheritDefault)
        XCTAssertEqual(model.layers.first(where: { $0.id == "pattern" })?.defaultValue(for: newTrack.id), .index(0))
        XCTAssertEqual(model.layers.first(where: { $0.id == "volume" })?.defaultValue(for: newTrack.id), .scalar(newTrack.mix.level * 127))
        XCTAssertEqual(model.selectedPattern(for: newTrack.id).sourceRef.mode, TrackSourceMode.generator)
        XCTAssertNotNil(model.selectedPattern(for: newTrack.id).sourceRef.generatorID)
    }

    func test_init_heals_poly_pattern_slots_with_nil_generator_ids() throws {
        let track = StepSequenceTrack(
            name: "Poly",
            trackType: .polyMelodic,
            pitches: [60, 64, 67],
            stepPattern: Array(repeating: true, count: 16),
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: PhraseLayerDefinition.defaultSet(for: [track]),
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: ClipPoolEntry.defaultPool
        )
        let nilGeneratorBank = TrackPatternBank(
            trackID: track.id,
            slots: (0..<TrackPatternBank.slotCount).map {
                TrackPatternSlot(slotIndex: $0, sourceRef: .generator(nil))
            }
        )

        let model = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: ClipPoolEntry.defaultPool,
            layers: PhraseLayerDefinition.defaultSet(for: [track]),
            routes: [],
            patternBanks: [nilGeneratorBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        XCTAssertEqual(model.selectedPattern(for: track.id).sourceRef.mode, TrackSourceMode.generator)
        XCTAssertNotNil(model.selectedPattern(for: track.id).sourceRef.generatorID)
        let polyGeneratorID = try XCTUnwrap(
            GeneratorPoolEntry.defaultPool.first(where: { $0.trackType == .polyMelodic })?.id
        )
        XCTAssertEqual(model.selectedPattern(for: track.id).sourceRef.generatorID, polyGeneratorID)
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
        var model = Project.empty

        let groupID = try XCTUnwrap(model.addDrumKit(.kit808))

        XCTAssertEqual(model.trackGroups.count, 1)
        XCTAssertEqual(model.trackGroups[0].id, groupID)
        XCTAssertEqual(model.trackGroups[0].memberIDs.count, DrumKitPreset.kit808.members.count)
        // Per-member destinations: each track has either .sample or .internalSampler (fallback).
        // None should be .inheritGroup since the new implementation assigns individual destinations.
        XCTAssertTrue(model.tracks.suffix(DrumKitPreset.kit808.members.count).allSatisfy { track in
            switch track.destination {
            case .sample, .internalSampler: return true
            default: return false
            }
        })
        // sharedDestination is nil — per-member samples, no shared sampler
        XCTAssertNil(model.trackGroups[0].sharedDestination)
        // noteMapping is empty — samples are pre-pitched, no MIDI transpose needed
        XCTAssertEqual(model.trackGroups[0].noteMapping, [:])
        XCTAssertTrue(model.phrases.allSatisfy { phrase in
            model.trackGroups[0].memberIDs.allSatisfy { memberID in
                phrase.cell(for: "pattern", trackID: memberID) == .inheritDefault
            }
        })
        XCTAssertEqual(model.selectedTrackID, model.trackGroups[0].memberIDs.first)
    }

    func test_set_phrase_cell_can_fan_out_to_multiple_tracks() throws {
        var model = Project.empty
        let groupID = try XCTUnwrap(model.addDrumKit(.kit808))
        let memberIDs = try XCTUnwrap(model.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        let intensityLayer = try XCTUnwrap(model.layers.first(where: { $0.id == "intensity" }))

        model.setPhraseCellMode(.single, layer: intensityLayer, trackIDs: memberIDs)
        model.setPhraseCell(.single(.scalar(0.72)), layerID: intensityLayer.id, trackIDs: memberIDs)

        XCTAssertTrue(memberIDs.allSatisfy { memberID in
            model.selectedPhrase.cell(for: intensityLayer.id, trackID: memberID) == .single(.scalar(0.72))
        })
    }

    func test_codable_roundtrip_preserves_layers_and_cells() throws {
        let track = StepSequenceTrack.default
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phraseID = UUID()
        let model = Project(
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
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        XCTAssertEqual(decoded.layers, model.layers)
        XCTAssertEqual(decoded.selectedPhrase.cells, model.selectedPhrase.cells)
        XCTAssertEqual(decoded.selectedPatternIndex(for: track.id), 3)
    }
}
