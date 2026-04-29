import Foundation
import XCTest
@testable import SequencerAI

final class SourceRefNormalizationTests: XCTestCase {
    func test_normalized_preserves_clipID_when_mode_is_generator() {
        let genID = UUID()
        let clipID = UUID()
        let ref = SourceRef(mode: .generator, generatorID: genID, clipID: clipID)

        let generator = GeneratorPoolEntry(
            id: genID,
            name: "Gen",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .defaultMono
        )

        let normalized = ref.normalized(
            trackType: .monoMelodic,
            generatorPool: [generator],
            clipPool: []
        )

        XCTAssertEqual(normalized.mode, .generator)
        XCTAssertEqual(normalized.generatorID, genID)
        XCTAssertEqual(normalized.clipID, clipID, "clipID must survive generator-mode normalization so bypass/remove can fall back to it")
    }

    func test_normalized_preserves_generatorID_when_mode_is_clip() {
        let genID = UUID()
        let clipID = UUID()
        let ref = SourceRef(mode: .clip, generatorID: genID, clipID: clipID)

        let clip = ClipPoolEntry(
            id: clipID,
            name: "Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: [60])
        )

        let normalized = ref.normalized(
            trackType: .monoMelodic,
            generatorPool: [],
            clipPool: [clip]
        )

        XCTAssertEqual(normalized.mode, .clip)
        XCTAssertEqual(normalized.clipID, clipID)
        XCTAssertEqual(normalized.generatorID, genID, "generatorID must survive clip-mode normalization so un-bypass can re-engage it")
    }

    func test_normalized_drops_source_only_generator_when_used_as_modifier() {
        let sourceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let progressionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let ref = SourceRef(
            mode: .generator,
            generatorID: sourceID,
            modifierGeneratorID: progressionID,
            modifierBypassed: false
        )
        let source = GeneratorPoolEntry(
            id: sourceID,
            name: "Poly",
            trackType: .polyMelodic,
            kind: .polyGenerator,
            params: GeneratorKind.polyGenerator.defaultParams
        )
        let progression = GeneratorPoolEntry(
            id: progressionID,
            name: "Progression Chords",
            trackType: .polyMelodic,
            kind: .progressionChordGenerator,
            params: .progressionChords(.default)
        )

        let normalized = ref.normalized(
            trackType: .polyMelodic,
            generatorPool: [source, progression],
            clipPool: []
        )

        XCTAssertEqual(normalized.generatorID, sourceID)
        XCTAssertNil(normalized.modifierGeneratorID)
        XCTAssertFalse(normalized.modifierBypassed)
    }
}
