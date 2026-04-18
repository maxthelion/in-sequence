import XCTest
@testable import SequencerAI

final class SeqAIDocumentModelTests: XCTestCase {
    func test_empty_has_version_1() {
        let model = SeqAIDocumentModel.empty
        XCTAssertEqual(model.version, 1)
        XCTAssertEqual(model.tracks, [.default])
        XCTAssertEqual(model.selectedTrackID, StepSequenceTrack.default.id)
        XCTAssertEqual(model.selectedTrack, .default)
        XCTAssertEqual(model.selectedTrack.stepAccents, Array(repeating: false, count: 16))
        XCTAssertEqual(model.selectedTrack.trackType, .instrument)
        XCTAssertEqual(model.selectedTrack.output, .midiOut)
        XCTAssertEqual(model.selectedTrack.audioInstrument, .builtInSynth)
        XCTAssertEqual(model.selectedTrack.mix, .default)
        XCTAssertEqual(model.phrases.count, 1)
        XCTAssertEqual(model.selectedPhrase.name, "Phrase A")
        XCTAssertEqual(model.selectedPhrase.instrumentSource(for: StepSequenceTrack.default.id), .manualMono)
    }

    func test_codable_roundtrip_preserves_empty() throws {
        let bassID = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
        let leadID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
        let phraseID = UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID()
        let original = SeqAIDocumentModel(
            version: 1,
            tracks: [
                StepSequenceTrack(
                    id: bassID,
                    name: "Bass",
                    trackType: .instrument,
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
                    trackType: .sliceLoop,
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
                    trackPipelines: [
                        PhraseTrackPipeline(trackID: bassID, instrumentSource: .clipReader)
                    ]
                )
            ],
            selectedPhraseID: phraseID
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_append_track_selects_new_track() {
        var model = SeqAIDocumentModel.empty

        model.appendTrack()

        XCTAssertEqual(model.tracks.count, 2)
        XCTAssertEqual(model.selectedTrack.id, model.tracks.last?.id)
        XCTAssertEqual(model.selectedTrack.name, "Track 2")
        XCTAssertEqual(model.selectedPhrase.trackPipelines.count, 2)
        XCTAssertEqual(model.selectedPhrase.instrumentSource(for: model.selectedTrack.id), .manualMono)
    }

    func test_append_phrase_selects_new_phrase() {
        var model = SeqAIDocumentModel.empty

        model.appendPhrase()

        XCTAssertEqual(model.phrases.count, 2)
        XCTAssertEqual(model.selectedPhraseID, model.phrases.last?.id)
        XCTAssertEqual(model.selectedPhrase.name, "Phrase B")
        XCTAssertEqual(model.selectedPhrase.trackPipelines.count, model.tracks.count)
    }

    func test_duplicate_selected_phrase_inserts_copy_after_current() {
        var model = SeqAIDocumentModel.empty

        model.duplicateSelectedPhrase()

        XCTAssertEqual(model.phrases.count, 2)
        XCTAssertEqual(model.selectedPhraseIndex, 1)
        XCTAssertEqual(model.selectedPhrase.name, "Phrase A Copy")
    }

    func test_remove_selected_track_falls_back_to_neighbour() {
        let trackTwo = StepSequenceTrack(name: "Track 2", pitches: [48], stepPattern: [true, false], stepAccents: [false, true], output: .auInstrument, velocity: 90, gateLength: 2)
        var model = SeqAIDocumentModel(
            version: 1,
            tracks: [.default, trackTwo],
            selectedTrackID: trackTwo.id
        )

        model.removeSelectedTrack()

        XCTAssertEqual(model.tracks, [.default])
        XCTAssertEqual(model.selectedTrackID, StepSequenceTrack.default.id)
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
        XCTAssertEqual(decoded.selectedTrack.trackType, .instrument)
        XCTAssertEqual(decoded.selectedTrack.output, .midiOut)
        XCTAssertEqual(decoded.selectedTrack.audioInstrument, .builtInSynth)
        XCTAssertEqual(decoded.selectedTrack.mix, .default)
        XCTAssertEqual(decoded.phrases.count, 1)
        XCTAssertEqual(decoded.selectedPhrase.instrumentSource(for: decoded.selectedTrack.id), .manualMono)
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

        XCTAssertEqual(decoded.selectedTrack.trackType, .drumRack)
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

        XCTAssertEqual(decoded.selectedTrack.trackType, .sliceLoop)
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

    func test_selected_phrase_can_store_phrase_scoped_instrument_source() {
        var model = SeqAIDocumentModel.empty

        var phrase = model.selectedPhrase
        phrase.setInstrumentSource(.template, for: model.selectedTrack.id)
        model.selectedPhrase = phrase

        XCTAssertEqual(model.selectedPhrase.instrumentSource(for: model.selectedTrack.id), .template)
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
              "trackPipelines": [
                {
                  "trackID": "11111111-1111-1111-1111-111111111111",
                  "instrumentSource": "clipReader"
                }
              ]
            }
          ],
          "selectedPhraseID": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: json)

        XCTAssertEqual(decoded.selectedPhrase.cellMode(for: .intensity, trackID: decoded.selectedTrack.id), .single)
        XCTAssertEqual(decoded.selectedPhrase.trackPipelines.first?.layerStates.count, PhraseAbstractKind.allCases.count)
    }
}

import UniformTypeIdentifiers

final class SeqAIDocumentFileTests: XCTestCase {
    func test_readable_content_types_includes_seqai_utype() {
        XCTAssertTrue(SeqAIDocument.readableContentTypes.contains(.seqAIDocument))
    }

    func test_default_initializer_creates_empty_model() {
        let doc = SeqAIDocument()
        XCTAssertEqual(doc.model, .empty)
    }
}
