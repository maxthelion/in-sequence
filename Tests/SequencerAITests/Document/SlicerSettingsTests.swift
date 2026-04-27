import XCTest
@testable import SequencerAI

final class SlicerSettingsTests: XCTestCase {
    func test_clamped_boundsGainAndTranspose() {
        let settings = SlicerSettings(gain: 40, transpose: -99, voiceMode: .polyphonic).clamped

        XCTAssertEqual(settings.gain, 12)
        XCTAssertEqual(settings.transpose, -48)
        XCTAssertEqual(settings.voiceMode, .polyphonic)
    }

    func test_default_isMonoUnity() {
        XCTAssertEqual(SlicerSettings.default.gain, 0)
        XCTAssertEqual(SlicerSettings.default.transpose, 0)
        XCTAssertEqual(SlicerSettings.default.voiceMode, .mono)
    }
}
