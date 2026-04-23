import AudioToolbox
import XCTest
@testable import SequencerAI

final class AudioInstrumentChoiceTests: XCTestCase {
    func test_deduplicated_removes_duplicate_choices_preserving_first_occurrence() {
        let duplicate = AudioInstrumentChoice(
            name: "Renoise Redux",
            manufacturerName: "Renoise",
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x52454458,
            componentManufacturer: 0x52454E4F
        )
        let unique = AudioInstrumentChoice(
            name: "MS-20 V",
            manufacturerName: "KORG",
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D533230,
            componentManufacturer: 0x4B4F5247
        )

        let deduplicated = AudioInstrumentChoice.deduplicated([
            duplicate,
            unique,
            duplicate,
        ])

        XCTAssertEqual(deduplicated, [duplicate, unique])
    }
}
