import XCTest
@testable import SequencerAI

final class PhrasePerformTimingPolicyTests: XCTestCase {
    func test_momentNeverUsesQuantisedBooleanArming() {
        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedBooleanArming(
            layerID: "mute",
            latchMode: .momentary,
            sessionArmingActive: true
        ))
    }

    func test_latchRequiresActiveSessionArming() {
        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedBooleanArming(
            layerID: "mute",
            latchMode: .latched,
            sessionArmingActive: false
        ))
    }

    func test_latchWithActiveSessionArmingUsesQuantisedBooleanLayersOnly() {
        XCTAssertTrue(PhrasePerformTimingPolicy.usesQuantisedBooleanArming(
            layerID: "mute",
            latchMode: .latched,
            sessionArmingActive: true
        ))

        XCTAssertTrue(PhrasePerformTimingPolicy.usesQuantisedBooleanArming(
            layerID: "fill-flag",
            latchMode: .latched,
            sessionArmingActive: true
        ))

        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedBooleanArming(
            layerID: "pattern",
            latchMode: .latched,
            sessionArmingActive: true
        ))
    }
}
