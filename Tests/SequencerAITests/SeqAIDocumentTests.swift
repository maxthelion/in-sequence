import XCTest
@testable import SequencerAI

final class SeqAIDocumentModelTests: XCTestCase {
    func test_phrase_layer_editor_kind_exposes_expected_modes() {
        XCTAssertEqual(PhraseLayerEditorKind.toggleBoolean.availableModes, [.single, .perBar])
        XCTAssertEqual(PhraseLayerEditorKind.indexedChoice.availableModes, [.single, .perBar])
        XCTAssertEqual(PhraseLayerEditorKind.continuousScalar.availableModes, [.single, .rampUp, .perBar, .drawn])
    }

    func test_phrase_abstract_layers_use_continuous_scalar_editor_kind() {
        XCTAssertTrue(PhraseAbstractKind.allCases.allSatisfy { $0.editorKind == .continuousScalar })
        XCTAssertTrue(PhraseAbstractKind.allCases.allSatisfy { $0.availableCellModes == [.single, .rampUp, .perBar, .drawn] })
    }

    func test_empty_has_version_1() {
        let model = SeqAIDocumentModel.empty

        XCTAssertEqual(model.version, 1)
        XCTAssertEqual(model.tracks, [.default])
        XCTAssertEqual(model.selectedTrackID, StepSequenceTrack.default.id)
        XCTAssertEqual(model.selectedTrack, .default)
        XCTAssertEqual(model.selectedTrack.stepAccents, Array(repeating: false, count: 16))
        XCTAssertEqual(model.selectedTrack.trackType, .monoMelodic)
        XCTAssertEqual(model.selectedTrack.output, .midiOut)
        XCTAssertEqual(
            model.selectedTrack.defaultDestination,
            .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        )
        XCTAssertEqual(model.selectedTrack.mix, .default)
        XCTAssertEqual(model.phrases.count, 1)
        XCTAssertEqual(model.selectedPhrase.name, "Phrase A")
        XCTAssertEqual(model.selectedPatternIndex(for: StepSequenceTrack.default.id), 0)
        XCTAssertEqual(model.selectedSourceMode(for: StepSequenceTrack.default.id), .generator)
        XCTAssertEqual(model.patternBanks.count, 1)
        XCTAssertEqual(model.patternBank(for: StepSequenceTrack.default.id).slots.count, 16)
        XCTAssertEqual(model.generatorPool.count, 3)
        XCTAssertTrue(model.clipPool.isEmpty)
    }

    func test_codable_roundtrip_preserves_pattern_banks() throws {
        let bassID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
        let leadID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
        let phraseID = UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID()
        let clipID = UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID()
        let original = SeqAIDocumentModel(
            version: 1,
            tracks: [
                StepSequenceTrack(
                    id: bassID,
                    name: "Bass",
                    trackType: .monoMelodic,
                    pitches: [36, 43],
                    stepPattern: [true, false, true, false],
                    stepAccents: [false, true, false, false],
                    output: .midiOut,
                    mix: TrackMixSettings(level: 0.65, pan: -0.25, isMuted: false),
                    velocity: 92,
                    gateLength: 2
                ),
                StepSequenceTrack(
                    id: leadID,
                    name: "Lead",
                    trackType: .slice,
                    pitches: [72, 76],
                    stepPattern: [true, true, false, true],
                    stepAccents: [true, false, false, true],
                    output: .auInstrument,
                    audioInstrument: .testInstrument,
                    mix: TrackMixSettings(level: 0.9, pan: 0.4, isMuted: true),
                    velocity: 101,
                    gateLength: 3
                )
            ],
            clipPool: [
                ClipPoolEntry(id: clipID, name: "Break Clip", trackType: .slice)
            ],
            patternBanks: [
                TrackPatternBank(
                    trackID: bassID,
                    slots: (0..<TrackPatternBank.slotCount).map {
                        TrackPatternSlot(slotIndex: $0, sourceRef: .generator(nil))
                    }
                ),
                TrackPatternBank(
                    trackID: leadID,
                    slots: (0..<TrackPatternBank.slotCount).map {
                        TrackPatternSlot(
                            slotIndex: $0,
                            name: $0 == 3 ? "Breakdown" : nil,
                            sourceRef: $0 == 3 ? .clip(clipID) : .generator(nil)
                        )
                    }
                )
            ],
            selectedTrackID: leadID,
            phrases: [
                PhraseModel(
                    id: phraseID,
                    name: "Verse",
                    lengthBars: 4,
                    stepsPerBar: 16,
                    abstractRows: PhraseAbstractKind.allCases.map {
                        PhraseAbstractRow(kind: $0, values: Array(repeating: 0.5, count: 64))
                    },
                    trackPatternIndexes: [
                        bassID: 0,
                        leadID: 3
                    ],
                    trackLayerStates: [
                        PhraseTrackLayerStateGroup(trackID: bassID)
                    ]
                )
            ],
            selectedPhraseID: phraseID
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.selectedPatternIndex(for: leadID), 3)
        XCTAssertEqual(decoded.selectedPattern(for: leadID).sourceRef, .clip(clipID))
    }

    func test_append_track_selects_new_track_and_adds_pattern_bank() {
        var model = SeqAIDocumentModel.empty

        model.appendTrack()

        XCTAssertEqual(model.tracks.count, 2)
        XCTAssertEqual(model.selectedTrack.id, model.tracks.last?.id)
        XCTAssertEqual(model.selectedTrack.name, "Track 2")
        XCTAssertEqual(model.patternBanks.count, 2)
        XCTAssertEqual(model.selectedPhrase.trackPatternIndexes.count, 2)
        XCTAssertEqual(model.selectedPatternIndex(for: model.selectedTrack.id), 0)
    }

    func test_append_phrase_selects_new_phrase_with_default_pattern_indexes() {
        var model = SeqAIDocumentModel.empty

        model.appendTrack()
        model.appendPhrase()

        XCTAssertEqual(model.phrases.count, 2)
        XCTAssertEqual(model.selectedPhraseID, model.phrases.last?.id)
        XCTAssertEqual(model.selectedPhrase.name, "Phrase B")
        XCTAssertEqual(model.selectedPhrase.trackPatternIndexes.count, model.tracks.count)
        XCTAssertTrue(model.selectedPhrase.trackPatternIndexes.values.allSatisfy { $0 == 0 })
    }

    func test_duplicate_selected_phrase_inserts_copy_after_current() {
        var model = SeqAIDocumentModel.empty

        model.duplicateSelectedPhrase()

        XCTAssertEqual(model.phrases.count, 2)
        XCTAssertEqual(model.selectedPhraseIndex, 1)
        XCTAssertEqual(model.selectedPhrase.name, "Phrase A Copy")
    }

    func test_remove_selected_track_falls_back_to_neighbour_and_drops_pattern_bank() {
        let trackTwo = StepSequenceTrack(name: "Track 2", pitches: [48], stepPattern: [true, false], stepAccents: [false, true], output: .auInstrument, velocity: 90, gateLength: 2)
        var model = SeqAIDocumentModel(
            version: 1,
            tracks: [.default, trackTwo],
            selectedTrackID: trackTwo.id
        )

        model.removeSelectedTrack()

        XCTAssertEqual(model.tracks, [.default])
        XCTAssertEqual(model.selectedTrackID, StepSequenceTrack.default.id)
        XCTAssertEqual(model.patternBanks.count, 1)
        XCTAssertEqual(model.selectedPhrase.trackPatternIndexes, [StepSequenceTrack.default.id: 0])
    }

    func test_init_normalizes_invalid_selected_track_id() {
        let alternateTrack = StepSequenceTrack(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888") ?? UUID(),
            name: "Alt",
            pitches: [65],
            stepPattern: [true, false],
            velocity: 100,
            gateLength: 4
        )
        let invalidID = UUID(uuidString: "99999999-9999-9999-9999-999999999999") ?? UUID()

        let model = SeqAIDocumentModel(
            version: 1,
            tracks: [.default, alternateTrack],
            selectedTrackID: invalidID
        )

        XCTAssertEqual(model.selectedTrackID, StepSequenceTrack.default.id)
        XCTAssertEqual(model.selectedTrack.id, StepSequenceTrack.default.id)
    }

    func test_decodes_legacy_single_track_documents() throws {
        let json = """
        {
          "version": 1,
          "primaryTrack": {
            "name": "Legacy",
            "pitches": [60, 67],
            "stepPattern": [true, false, true, false],
            "velocity": 99,
            "gateLength": 3
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertEqual(decoded.tracks.count, 1)
        XCTAssertEqual(decoded.selectedTrack.name, "Legacy")
        XCTAssertEqual(decoded.selectedTrack.stepAccents, [false, false, false, false])
        XCTAssertEqual(decoded.selectedTrack.trackType, .monoMelodic)
        XCTAssertEqual(decoded.selectedTrack.output, .midiOut)
        XCTAssertEqual(
            decoded.selectedTrack.defaultDestination,
            .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        )
        XCTAssertEqual(decoded.selectedTrack.mix, .default)
        XCTAssertEqual(decoded.phrases.count, 1)
        XCTAssertEqual(decoded.selectedPatternIndex(for: decoded.selectedTrack.id), 0)
        XCTAssertEqual(decoded.selectedSourceMode(for: decoded.selectedTrack.id), .generator)
        XCTAssertEqual(decoded.generatorPool.count, 3)
    }

    func test_decodes_track_type_when_present() throws {
        let json = """
        {
          "version": 1,
          "tracks": [
            {
              "id": "44444444-4444-4444-4444-444444444444",
              "name": "Drums",
              "trackType": "drumRack",
              "pitches": [36, 38, 42],
              "stepPattern": [true, false, true, false],
              "stepAccents": [false, false, true, false],
              "output": "midiOut",
              "mix": {
                "level": 1,
                "pan": 0,
                "isMuted": false
              },
              "velocity": 100,
              "gateLength": 4
            }
          ],
          "selectedTrackID": "44444444-4444-4444-4444-444444444444"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertEqual(decoded.selectedTrack.trackType, .monoMelodic)
    }

    func test_maps_legacy_source_to_track_type_when_present() throws {
        let json = """
        {
          "version": 1,
          "tracks": [
            {
              "id": "55555555-5555-5555-5555-555555555555",
              "name": "Loop",
              "source": "sliceLoop",
              "pitches": [60, 62],
              "stepPattern": [true, false, true, false],
              "stepAccents": [false, false, false, true],
              "output": "midiOut",
              "velocity": 90,
              "gateLength": 2
            }
          ],
          "selectedTrackID": "55555555-5555-5555-5555-555555555555"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertEqual(decoded.selectedTrack.trackType, .slice)
    }

    func test_decodes_legacy_output_and_audio_instrument_into_voicing() throws {
        let testInstrument = AudioInstrumentChoice.testInstrument
        let json = """
        {
          "version": 1,
          "tracks": [
            {
              "id": "12121212-3434-5656-7878-909090909090",
              "name": "Lead",
              "trackType": "instrument",
              "pitches": [60, 64, 67],
              "stepPattern": [true, false, true, false],
              "stepAccents": [false, false, true, false],
              "output": "auInstrument",
              "audioInstrument": {
                "name": "Test Synth",
                "manufacturerName": "Codex",
                "componentType": \(testInstrument.componentType),
                "componentSubType": \(testInstrument.componentSubType),
                "componentManufacturer": \(testInstrument.componentManufacturer)
              },
              "velocity": 100,
              "gateLength": 4
            }
          ],
          "selectedTrackID": "12121212-3434-5656-7878-909090909090"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertEqual(decoded.selectedTrack.output, .auInstrument)
        XCTAssertEqual(decoded.selectedTrack.audioInstrument, .testInstrument)
        XCTAssertEqual(
            decoded.selectedTrack.defaultDestination,
            .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil)
        )
    }

    func test_cycle_step_moves_between_off_on_and_accented() {
        var track = StepSequenceTrack(name: "Lead", pitches: [72], stepPattern: [false], velocity: 100, gateLength: 4)

        track.cycleStep(at: 0)
        XCTAssertEqual(track.stepPattern, [true])
        XCTAssertEqual(track.stepAccents, [false])

        track.cycleStep(at: 0)
        XCTAssertEqual(track.stepPattern, [true])
        XCTAssertEqual(track.stepAccents, [true])

        track.cycleStep(at: 0)
        XCTAssertEqual(track.stepPattern, [false])
        XCTAssertEqual(track.stepAccents, [false])
    }

    func test_selected_phrase_can_store_pattern_index_per_track() {
        var model = SeqAIDocumentModel.empty

        model.setSelectedPatternIndex(7, for: model.selectedTrack.id)

        XCTAssertEqual(model.selectedPhrase.patternIndex(for: model.selectedTrack.id), 7)
    }

    func test_selected_track_pattern_slot_can_change_source_mode() {
        var model = SeqAIDocumentModel.empty

        model.setPatternSourceMode(.clip, for: model.selectedTrack.id, slotIndex: 0)

        XCTAssertEqual(model.selectedPattern(for: model.selectedTrack.id).sourceRef.mode, .clip)
    }

    func test_selected_track_pattern_slot_can_store_name() {
        var model = SeqAIDocumentModel.empty

        model.setPatternName("Verse Pulse", for: model.selectedTrack.id, slotIndex: 2)

        XCTAssertEqual(model.patternBank(for: model.selectedTrack.id).slot(at: 2).name, "Verse Pulse")
    }

    func test_selected_phrase_can_store_phrase_cell_mode_per_track_and_layer() {
        var model = SeqAIDocumentModel.empty

        var phrase = model.selectedPhrase
        phrase.setCellMode(.drawn, for: .tension, trackID: model.selectedTrack.id)
        model.selectedPhrase = phrase

        XCTAssertEqual(model.selectedPhrase.cellMode(for: .tension, trackID: model.selectedTrack.id), .drawn)
    }

    func test_phrase_pipeline_decodes_missing_layer_states_with_defaults() throws {
        let json = """
        {
          "version": 1,
          "tracks": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Lead",
              "trackType": "instrument",
              "pitches": [60, 64, 67, 72],
              "stepPattern": [true, true, true, true],
              "stepAccents": [false, false, false, false],
              "output": "midiOut",
              "velocity": 100,
              "gateLength": 4
            }
          ],
          "selectedTrackID": "11111111-1111-1111-1111-111111111111",
          "phrases": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Phrase A",
              "lengthBars": 4,
              "stepsPerBar": 16,
              "abstractRows": [
                { "kind": "intensity", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "density", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "register", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "tension", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "variance", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "brightness", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] }
              ],
              "trackPatternIndexes": {
                "11111111-1111-1111-1111-111111111111": 4
              }
            }
          ],
          "selectedPhraseID": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertEqual(decoded.selectedPhrase.cellMode(for: .intensity, trackID: decoded.selectedTrack.id), .single)
        XCTAssertEqual(decoded.selectedPhrase.trackLayerStates.first?.layerStates.count, PhraseAbstractKind.allCases.count)
        XCTAssertEqual(decoded.selectedPatternIndex(for: decoded.selectedTrack.id), 4)
    }

    func test_legacy_phrase_source_refs_migrate_into_pattern_banks() throws {
        let json = """
        {
          "version": 1,
          "generatorPool": [
            {
              "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1",
              "name": "Manual Mono",
              "trackType": "instrument",
              "kind": "manualMono"
            }
          ],
          "tracks": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Lead",
              "trackType": "instrument",
              "pitches": [60],
              "stepPattern": [true, false, true, false],
              "stepAccents": [false, false, false, false],
              "output": "midiOut",
              "velocity": 100,
              "gateLength": 4
            }
          ],
          "selectedTrackID": "11111111-1111-1111-1111-111111111111",
          "phrases": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Phrase A",
              "lengthBars": 4,
              "stepsPerBar": 16,
              "abstractRows": [
                { "kind": "intensity", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "density", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "register", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "tension", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "variance", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "brightness", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] }
              ],
              "sourceRefs": [
                {
                  "trackID": "11111111-1111-1111-1111-111111111111",
                  "sourceRef": {
                    "mode": "clip"
                  }
                }
              ]
            }
          ],
          "selectedPhraseID": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertEqual(decoded.selectedPatternIndex(for: decoded.selectedTrack.id), 0)
        XCTAssertEqual(decoded.selectedPattern(for: decoded.selectedTrack.id).sourceRef.mode, .clip)
        XCTAssertTrue(decoded.selectedPhrase.legacySourceRefs.isEmpty)
    }

    func test_legacy_template_source_migrates_to_generator_pattern_slot() throws {
        let json = """
        {
          "version": 1,
          "tracks": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Lead",
              "trackType": "instrument",
              "pitches": [60],
              "stepPattern": [true, false, true, false],
              "stepAccents": [false, false, false, false],
              "output": "midiOut",
              "velocity": 100,
              "gateLength": 4
            }
          ],
          "selectedTrackID": "11111111-1111-1111-1111-111111111111",
          "phrases": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Phrase A",
              "lengthBars": 4,
              "stepsPerBar": 16,
              "abstractRows": [
                { "kind": "intensity", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "density", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "register", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "tension", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "variance", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] },
                { "kind": "brightness", "sourceMode": "authored", "values": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0] }
              ],
              "sourceRefs": [
                {
                  "trackID": "11111111-1111-1111-1111-111111111111",
                  "instrumentSource": "template"
                }
              ]
            }
          ],
          "selectedPhraseID": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertEqual(decoded.selectedSourceMode(for: decoded.selectedTrack.id), .generator)
    }

    func test_new_document_starts_with_empty_routes() {
        XCTAssertTrue(SeqAIDocumentModel.empty.routes.isEmpty)
    }

    func test_document_roundtrip_preserves_routes() throws {
        var model = SeqAIDocumentModel.empty
        let route = Route(
            source: .track(model.selectedTrack.id),
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        )
        model.routes = [route]

        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: data)

        XCTAssertEqual(decoded.routes, [route])
    }

    func test_routes_helpers_filter_by_source_and_target_track() {
        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID(),
            name: "Source",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        let targetTrack = StepSequenceTrack(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID(),
            name: "Target",
            pitches: [67],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        let phrase = PhraseModel.default(tracks: [sourceTrack, targetTrack])
        let sourcedRoute = Route(source: .track(sourceTrack.id), destination: .voicing(targetTrack.id))
        let unrelatedRoute = Route(
            source: .track(targetTrack.id),
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        )
        let model = SeqAIDocumentModel(
            version: 1,
            tracks: [sourceTrack, targetTrack],
            routes: [sourcedRoute, unrelatedRoute],
            selectedTrackID: sourceTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        XCTAssertEqual(model.routesSourced(from: sourceTrack.id), [sourcedRoute])
        XCTAssertEqual(model.routesTargeting(targetTrack.id), [sourcedRoute])
    }

    func test_make_default_route_prefers_another_track_voicing() {
        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "AAAAAAA1-1111-1111-1111-111111111111") ?? UUID(),
            name: "Source",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        let targetTrack = StepSequenceTrack(
            id: UUID(uuidString: "BBBBBBB2-2222-2222-2222-222222222222") ?? UUID(),
            name: "Target",
            pitches: [67],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        let model = SeqAIDocumentModel(version: 1, tracks: [sourceTrack, targetTrack], selectedTrackID: sourceTrack.id)

        let route = model.makeDefaultRoute(from: sourceTrack.id)

        XCTAssertEqual(route.source, .track(sourceTrack.id))
        XCTAssertEqual(route.destination, .voicing(targetTrack.id))
    }

    func test_upsert_and_remove_route_mutate_document_routes() {
        var model = SeqAIDocumentModel.empty
        let route = Route(
            id: UUID(uuidString: "CCCCCCC3-3333-3333-3333-333333333333") ?? UUID(),
            source: .track(model.selectedTrack.id),
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        )

        model.upsertRoute(route)
        XCTAssertEqual(model.routes, [route])

        var editedRoute = route
        editedRoute.enabled = false
        model.upsertRoute(editedRoute)
        XCTAssertEqual(model.routes, [editedRoute])

        model.removeRoute(id: route.id)
        XCTAssertTrue(model.routes.isEmpty)
    }

    func test_track_midi_helpers_update_default_destination() {
        var track = StepSequenceTrack.default

        track.setMIDIPort(MIDIEndpointName(displayName: "External Port", isVirtual: false))
        track.setMIDIChannel(5)
        track.setMIDINoteOffset(12)

        XCTAssertEqual(
            track.defaultDestination,
            .midi(
                port: MIDIEndpointName(displayName: "External Port", isVirtual: false),
                channel: 5,
                noteOffset: 12
            )
        )
        XCTAssertEqual(track.midiPortName?.displayName, "External Port")
        XCTAssertEqual(track.midiChannel, 5)
        XCTAssertEqual(track.midiNoteOffset, 12)
    }

    func test_legacy_document_without_routes_decodes_empty_route_list() throws {
        let json = """
        {
          "version": 1,
          "tracks": [
            {
              "id": "88888888-8888-8888-8888-888888888888",
              "name": "Lead",
              "trackType": "instrument",
              "pitches": [60],
              "stepPattern": [true],
              "stepAccents": [false],
              "voicing": {
                "destinations": {
                  "default": {
                    "auInstrument": {
                      "componentID": {
                        "type": "aumu",
                        "subtype": "DLSs",
                        "manufacturer": "appl",
                        "version": 0
                      },
                      "stateBlob": null
                    }
                  }
                }
              },
              "mix": {
                "level": 0.8,
                "pan": 0.0,
                "isMuted": false
              },
              "velocity": 100,
              "gateLength": 4
            }
          ],
          "selectedTrackID": "88888888-8888-8888-8888-888888888888",
          "phrases": [
            {
              "id": "99999999-9999-9999-9999-999999999999",
              "name": "Phrase A",
              "lengthBars": 8,
              "stepsPerBar": 16,
              "abstractRows": [],
              "trackPatternIndexes": {
                "88888888-8888-8888-8888-888888888888": 0
              },
              "trackLayerStates": []
            }
          ],
          "selectedPhraseID": "99999999-9999-9999-9999-999999999999"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertTrue(decoded.routes.isEmpty)
    }
}
