import XCTest
@testable import SequencerAI

final class PhraseCellPreviewTests: XCTestCase {
    private let track = StepSequenceTrack(
        id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
        name: "Track",
        trackType: .monoMelodic,
        pitches: [60],
        stepPattern: Array(repeating: true, count: 16),
        velocity: 100,
        gateLength: 4
    )

    func test_toggled_boolean_value_uses_normalized_layer_semantics() {
        let muteLayer = PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "mute" })!

        XCTAssertEqual(toggledBooleanValue(.scalar(0), for: muteLayer), .bool(true))
        XCTAssertEqual(toggledBooleanValue(.scalar(1), for: muteLayer), .bool(false))
        XCTAssertEqual(toggledBooleanValue(.index(0), for: muteLayer), .bool(true))
        XCTAssertEqual(toggledBooleanValue(.index(1), for: muteLayer), .bool(false))
    }

    func test_cycled_value_wraps_pattern_indexes() {
        let patternLayer = PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "pattern" })!

        XCTAssertEqual(cycledValue(.index(15), for: patternLayer), .index(0))
        XCTAssertEqual(cycledValue(.index(0), for: patternLayer), .index(1))
    }

    func test_cycled_value_advances_scalar_by_quarters_of_layer_range() {
        let volumeLayer = PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "volume" })!

        XCTAssertEqual(cycledValue(.scalar(0), for: volumeLayer), .scalar(31.75))
        XCTAssertEqual(cycledValue(.scalar(127), for: volumeLayer), .scalar(0))
    }
}
