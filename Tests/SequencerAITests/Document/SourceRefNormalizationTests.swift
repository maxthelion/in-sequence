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
}
