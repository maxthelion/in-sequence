import XCTest
@testable import SequencerAI

final class PhrasePerformTimingPolicyTests: XCTestCase {
    func test_momentNeverUsesQuantisedLayerArming() {
        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: "mute",
            latchMode: .momentary,
            sessionArmingActive: true
        ))
    }

    func test_latchRequiresActiveSessionArming() {
        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: "mute",
            latchMode: .latched,
            sessionArmingActive: false
        ))
    }

    func test_latchWithActiveSessionArmingUsesQuantisedBoundaryLayersOnly() {
        XCTAssertTrue(PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: "mute",
            latchMode: .latched,
            sessionArmingActive: true
        ))

        XCTAssertTrue(PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: "fill-flag",
            latchMode: .latched,
            sessionArmingActive: true
        ))

        XCTAssertTrue(PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: "pattern",
            latchMode: .latched,
            sessionArmingActive: true
        ))

        XCTAssertFalse(PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: "volume",
            latchMode: .latched,
            sessionArmingActive: true
        ))
    }
}
