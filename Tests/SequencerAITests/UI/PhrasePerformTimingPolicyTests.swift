import XCTest
@testable import SequencerAI

final class PhrasePerformTimingPolicyTests: XCTestCase {
    func test_momentNeverUsesQuantisedMuteArming() {
        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedMuteArming(
            layerID: "mute",
            latchMode: .momentary,
            sessionArmingActive: true
        ))
    }

    func test_latchRequiresActiveSessionArming() {
        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedMuteArming(
            layerID: "mute",
            latchMode: .latched,
            sessionArmingActive: false
        ))
    }

    func test_latchWithActiveSessionArmingUsesQuantisedMuteOnly() {
        XCTAssertTrue(PhrasePerformTimingPolicy.usesQuantisedMuteArming(
            layerID: "mute",
            latchMode: .latched,
            sessionArmingActive: true
        ))

        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedMuteArming(
            layerID: "fill-flag",
            latchMode: .latched,
            sessionArmingActive: true
        ))

        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedMuteArming(
            layerID: "pattern",
            latchMode: .latched,
            sessionArmingActive: true
        ))
    }
}
