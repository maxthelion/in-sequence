import XCTest
@testable import SequencerAI

/// Forward-only phrase inheritance.
///
/// An `.inheritDefault` cell resolves to the value of the nearest *preceding*
/// phrase (in song order) that set an explicit value for the same layer+track,
/// falling back to the layer's stored default when none precedes it. Editing a
/// phrase must affect only that phrase and the following inheritors — never
/// earlier ones.
final class PhraseForwardInheritTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTrack() -> StepSequenceTrack {
        StepSequenceTrack.default
    }

    /// A boolean layer (mute) is the cleanest layer for cascade semantics.
    private func muteLayer(for track: StepSequenceTrack) -> PhraseLayerDefinition {
        PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "mute" })!
    }

    private func intensityLayer(for track: StepSequenceTrack) -> PhraseLayerDefinition {
        PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "intensity" })!
    }

    /// Build a chain of `count` phrases, all cells `.inheritDefault` for the
    /// given layer/track.
    private func makeChain(
        count: Int,
        layer: PhraseLayerDefinition,
        track: StepSequenceTrack
    ) -> [PhraseModel] {
        (0..<count).map { _ in
            PhraseModel(
                id: UUID(),
                name: "P",
                lengthBars: 1,
                stepsPerBar: 4,
                cells: [
                    PhraseCellAssignment(trackID: track.id, layerID: layer.id, cell: .inheritDefault),
                ]
            )
        }
    }

    private func resolvedBool(
        _ phrase: PhraseModel,
        layer: PhraseLayerDefinition,
        track: StepSequenceTrack,
        inherited: PhraseInheritedDefaults.Resolved
    ) -> Bool {
        if case let .bool(value) = phrase.resolvedValue(
            for: layer,
            trackID: track.id,
            stepIndex: 0,
            inherited: inherited
        ) {
            return value
        }
        XCTFail("expected bool value")
        return false
    }

    // MARK: - First phrase falls back to layer default

    func test_first_phrase_inheriting_falls_back_to_layer_default() {
        let track = makeTrack()
        var layer = muteLayer(for: track)
        layer.defaults[track.id] = .bool(true) // layer default = muted

        let phrases = makeChain(count: 3, layer: layer, track: track)
        let inherited = PhraseInheritedDefaults.build(phrases: phrases, layers: [layer])

        // No preceding explicit value anywhere -> all resolve to layer default.
        for phrase in phrases {
            XCTAssertTrue(
                resolvedBool(phrase, layer: layer, track: track, inherited: inherited.resolved(for: phrase.id)),
                "with no preceding explicit value every phrase must use the layer default"
            )
        }
    }

    // MARK: - Forward propagation chain

    func test_explicit_phrase2_propagates_forward_to_phrase3_and_4() {
        let track = makeTrack()
        var layer = muteLayer(for: track)
        layer.defaults[track.id] = .bool(false)

        var phrases = makeChain(count: 4, layer: layer, track: track)
        // Phrase index 1 (the 2nd) becomes explicitly muted.
        phrases[1].setCell(.single(.bool(true)), for: layer.id, trackID: track.id)

        let inherited = PhraseInheritedDefaults.build(phrases: phrases, layers: [layer])

        // Phrase 1 (index 0): nothing precedes -> layer default (false).
        XCTAssertFalse(resolvedBool(phrases[0], layer: layer, track: track, inherited: inherited.resolved(for: phrases[0].id)))
        // Phrase 2 (index 1): explicit true.
        XCTAssertTrue(resolvedBool(phrases[1], layer: layer, track: track, inherited: inherited.resolved(for: phrases[1].id)))
        // Phrase 3 & 4 inherit forward from phrase 2 -> true.
        XCTAssertTrue(resolvedBool(phrases[2], layer: layer, track: track, inherited: inherited.resolved(for: phrases[2].id)))
        XCTAssertTrue(resolvedBool(phrases[3], layer: layer, track: track, inherited: inherited.resolved(for: phrases[3].id)))
    }

    // MARK: - Editing a later phrase must NOT change earlier ones

    func test_editing_phrase3_does_not_change_phrase1_or_phrase2() {
        let track = makeTrack()
        var layer = muteLayer(for: track)
        layer.defaults[track.id] = .bool(false)

        var phrases = makeChain(count: 4, layer: layer, track: track)
        // Phrase 2 explicit true; phrases 3/4 inherit it.
        phrases[1].setCell(.single(.bool(true)), for: layer.id, trackID: track.id)

        // Now edit phrase 3 (index 2) to an explicit value (false).
        phrases[2].setCell(.single(.bool(false)), for: layer.id, trackID: track.id)

        let inherited = PhraseInheritedDefaults.build(phrases: phrases, layers: [layer])

        // Earlier phrases are unchanged.
        XCTAssertFalse(resolvedBool(phrases[0], layer: layer, track: track, inherited: inherited.resolved(for: phrases[0].id)),
                       "editing phrase 3 must not change phrase 1")
        XCTAssertTrue(resolvedBool(phrases[1], layer: layer, track: track, inherited: inherited.resolved(for: phrases[1].id)),
                      "editing phrase 3 must not change phrase 2")
        // Phrase 3 explicit false.
        XCTAssertFalse(resolvedBool(phrases[2], layer: layer, track: track, inherited: inherited.resolved(for: phrases[2].id)))
        // Phrase 4 now inherits phrase 3's false (nearest preceding explicit).
        XCTAssertFalse(resolvedBool(phrases[3], layer: layer, track: track, inherited: inherited.resolved(for: phrases[3].id)),
                       "phrase 4 inherits the nearest preceding explicit value, which is now phrase 3")
    }

    // MARK: - Nearest-preceding semantics with multiple explicit phrases

    func test_nearest_preceding_explicit_wins() {
        let track = makeTrack()
        var layer = intensityLayer(for: track)
        layer.defaults[track.id] = .scalar(0)

        var phrases = makeChain(count: 5, layer: layer, track: track)
        phrases[0].setCell(.single(.scalar(0.2)), for: layer.id, trackID: track.id)
        phrases[2].setCell(.single(.scalar(0.7)), for: layer.id, trackID: track.id)
        // phrases 1, 3, 4 inherit.

        let inherited = PhraseInheritedDefaults.build(phrases: phrases, layers: [layer])

        XCTAssertEqual(phrases[0].resolvedValue(for: layer, trackID: track.id, stepIndex: 0, inherited: inherited.resolved(for: phrases[0].id)), .scalar(0.2))
        XCTAssertEqual(phrases[1].resolvedValue(for: layer, trackID: track.id, stepIndex: 0, inherited: inherited.resolved(for: phrases[1].id)), .scalar(0.2),
                       "phrase 2 inherits from phrase 1")
        XCTAssertEqual(phrases[2].resolvedValue(for: layer, trackID: track.id, stepIndex: 0, inherited: inherited.resolved(for: phrases[2].id)), .scalar(0.7))
        XCTAssertEqual(phrases[3].resolvedValue(for: layer, trackID: track.id, stepIndex: 0, inherited: inherited.resolved(for: phrases[3].id)), .scalar(0.7),
                       "phrase 4 inherits the nearer phrase 3, not phrase 1")
        XCTAssertEqual(phrases[4].resolvedValue(for: layer, trackID: track.id, stepIndex: 0, inherited: inherited.resolved(for: phrases[4].id)), .scalar(0.7))
    }

    // MARK: - Boundary cases

    func test_empty_phrase_list() {
        let track = makeTrack()
        let layer = muteLayer(for: track)
        let inherited = PhraseInheritedDefaults.build(phrases: [], layers: [layer])
        // resolved(for:) on an unknown id returns an empty Resolved -> nil lookups.
        XCTAssertNil(inherited.resolved(for: UUID()).value(layerID: layer.id, trackID: track.id))
    }

    func test_single_phrase_inheriting_uses_layer_default() {
        let track = makeTrack()
        var layer = muteLayer(for: track)
        layer.defaults[track.id] = .bool(true)
        let phrases = makeChain(count: 1, layer: layer, track: track)
        let inherited = PhraseInheritedDefaults.build(phrases: phrases, layers: [layer])
        XCTAssertTrue(resolvedBool(phrases[0], layer: layer, track: track, inherited: inherited.resolved(for: phrases[0].id)))
    }

    func test_all_inherit_resolves_to_default_throughout() {
        let track = makeTrack()
        var layer = intensityLayer(for: track)
        layer.defaults[track.id] = .scalar(0.33)
        let phrases = makeChain(count: 6, layer: layer, track: track)
        let inherited = PhraseInheritedDefaults.build(phrases: phrases, layers: [layer])
        for phrase in phrases {
            XCTAssertEqual(
                phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0, inherited: inherited.resolved(for: phrase.id)),
                .scalar(0.33)
            )
        }
    }

    // MARK: - Legacy / nil-inherited behaviour preserved

    func test_nil_inherited_falls_back_to_layer_default_legacy() {
        let track = makeTrack()
        var layer = muteLayer(for: track)
        layer.defaults[track.id] = .bool(true)
        let phrase = makeChain(count: 1, layer: layer, track: track)[0]
        // Calling resolvedValue WITHOUT inherited context (the legacy 25 call
        // sites) must still resolve to the layer default.
        XCTAssertEqual(phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0), .bool(true))
    }

    // MARK: - Codable round-trip (incl. legacy doc with no per-cell source)

    func test_codable_round_trip_preserves_inheritance_resolution() throws {
        let track = makeTrack()
        var layer = muteLayer(for: track)
        layer.defaults[track.id] = .bool(false)

        var phrases = makeChain(count: 3, layer: layer, track: track)
        phrases[0].setCell(.single(.bool(true)), for: layer.id, trackID: track.id)

        // Round-trip each phrase through the document codec.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decodedPhrases = try phrases.map { phrase -> PhraseModel in
            let data = try encoder.encode(phrase)
            return try decoder.decode(PhraseModel.self, from: data)
        }
        XCTAssertEqual(decodedPhrases, phrases, "codable round-trip must be lossless")

        let inherited = PhraseInheritedDefaults.build(phrases: decodedPhrases, layers: [layer])
        XCTAssertTrue(resolvedBool(decodedPhrases[0], layer: layer, track: track, inherited: inherited.resolved(for: decodedPhrases[0].id)))
        XCTAssertTrue(resolvedBool(decodedPhrases[1], layer: layer, track: track, inherited: inherited.resolved(for: decodedPhrases[1].id)),
                      "inherited value survives codable round-trip")
        XCTAssertTrue(resolvedBool(decodedPhrases[2], layer: layer, track: track, inherited: inherited.resolved(for: decodedPhrases[2].id)))
    }

    func test_legacy_phrase_json_without_new_fields_still_decodes() throws {
        // A minimal legacy phrase JSON (no inheritance-source field on cells).
        // The cell uses the existing `.inheritDefault` representation.
        let trackID = UUID()
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy",
          "lengthBars": 2,
          "stepsPerBar": 16,
          "cells": [
            {
              "trackID": "\(trackID.uuidString)",
              "layerID": "mute",
              "cell": { "inheritDefault": {} }
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(PhraseModel.self, from: data)
        XCTAssertEqual(decoded.cells.count, 1)
        XCTAssertEqual(decoded.cell(for: "mute", trackID: trackID).editMode, .inheritDefault)
    }

    // MARK: - Engine compile path produces forward-only values

    func test_engine_compile_path_resolves_forward_only_mute() throws {
        let track = makeTrack()
        var project = Project.empty
        project.tracks = [track]
        project.layers = PhraseLayerDefinition.defaultSet(for: [track])
        let layer = project.layers.first(where: { $0.id == "mute" })!

        // Three phrases: P1 inherit, P2 explicit muted, P3 inherit.
        var p1 = PhraseModel(id: UUID(), name: "P1", lengthBars: 1, stepsPerBar: 4,
                             cells: [PhraseCellAssignment(trackID: track.id, layerID: layer.id, cell: .inheritDefault)])
        var p2 = p1
        p2.id = UUID(); p2.name = "P2"
        p2.setCell(.single(.bool(true)), for: layer.id, trackID: track.id)
        var p3 = p1
        p3.id = UUID(); p3.name = "P3"

        p1 = p1.synced(with: project.tracks, layers: project.layers)
        p2 = p2.synced(with: project.tracks, layers: project.layers)
        p3 = p3.synced(with: project.tracks, layers: project.layers)
        project.phrases = [p1, p2, p3]
        project.selectedPhraseID = p1.id

        let snapshot = SequencerSnapshotCompiler.compile(project: project)

        func muteAtStep0(_ phraseID: UUID) -> Bool {
            let buffer = snapshot.phraseBuffersByID[phraseID]!
            return buffer.trackStates[track.id]!.mute[0]
        }

        XCTAssertFalse(muteAtStep0(p1.id), "P1 has no preceding explicit value -> layer default (unmuted)")
        XCTAssertTrue(muteAtStep0(p2.id), "P2 explicit muted")
        XCTAssertTrue(muteAtStep0(p3.id), "P3 inherits P2 forward -> muted")
    }
}
