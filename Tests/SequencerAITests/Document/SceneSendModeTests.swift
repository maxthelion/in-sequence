import XCTest
@testable import SequencerAI

/// R4: the per-track scene-send selector (A / A+B / B) is a pure VIEW over the
/// two persisted send gains — no new persisted field. These pin the derivation
/// (gains → mode, exact-match only) and the preset gains (mode → gains).
final class SceneSendModeTests: XCTestCase {
    func test_presetGains_perMode() {
        XCTAssertEqual(SceneSendMode.a.sendGains.sendA, 1)
        XCTAssertEqual(SceneSendMode.a.sendGains.sendB, 0)
        XCTAssertEqual(SceneSendMode.ab.sendGains.sendA, 1)
        XCTAssertEqual(SceneSendMode.ab.sendGains.sendB, 1)
        XCTAssertEqual(SceneSendMode.b.sendGains.sendA, 0)
        XCTAssertEqual(SceneSendMode.b.sendGains.sendB, 1)
    }

    func test_derivation_matchesPresetsExactly() {
        XCTAssertEqual(SceneSendMode(sendA: 1, sendB: 0), .a)
        XCTAssertEqual(SceneSendMode(sendA: 1, sendB: 1), .ab)
        XCTAssertEqual(SceneSendMode(sendA: 0, sendB: 1), .b)
    }

    func test_derivation_nonPresetGainsAreCustom() {
        XCTAssertNil(SceneSendMode(sendA: 0, sendB: 0)) // both off = no scene
        XCTAssertNil(SceneSendMode(sendA: 0.5, sendB: 0.5)) // partial
        XCTAssertNil(SceneSendMode(sendA: 1, sendB: 0.5))
        XCTAssertNil(SceneSendMode(sendA: 0.9999, sendB: 0)) // near-but-not-exact
    }

    func test_roundTrip_modeToGainsToMode() {
        for mode in SceneSendMode.allCases {
            let gains = mode.sendGains
            XCTAssertEqual(SceneSendMode(sendA: gains.sendA, sendB: gains.sendB), mode)
        }
    }

    func test_trackMixSettings_sceneSendModeAccessor() {
        var mix = TrackMixSettings.default
        mix.sendA = 1
        mix.sendB = 0
        XCTAssertEqual(mix.sceneSendMode, .a)

        mix.sendB = 1
        XCTAssertEqual(mix.sceneSendMode, .ab)

        mix.sendA = 0
        XCTAssertEqual(mix.sceneSendMode, .b)

        // A non-preset combination reads as Custom (nil).
        mix.sendA = 0.3
        mix.sendB = 0.7
        XCTAssertNil(mix.sceneSendMode)
    }
}
