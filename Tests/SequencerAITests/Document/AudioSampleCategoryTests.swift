// Tests/SequencerAITests/Document/AudioSampleCategoryTests.swift
import XCTest
@testable import SequencerAI

final class AudioSampleCategoryTests: XCTestCase {
    func test_isDrumVoice_trueForDrumCases() {
        let drumCases: [AudioSampleCategory] = [
            .kick, .snare, .sidestick, .clap, .hatClosed, .hatOpen, .hatPedal,
            .tomLow, .tomMid, .tomHi, .ride, .crash, .cowbell, .tambourine, .shaker, .percussion
        ]
        for c in drumCases { XCTAssertTrue(c.isDrumVoice, "\(c) should be drum voice") }
    }

    func test_isDrumVoice_falseForUnknown() {
        XCTAssertFalse(AudioSampleCategory.unknown.isDrumVoice)
    }

    func test_voiceTagBridge_knownTags() {
        XCTAssertEqual(AudioSampleCategory(voiceTag: "kick"), .kick)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "snare"), .snare)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "hat-closed"), .hatClosed)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "hat-open"), .hatOpen)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "clap"), .clap)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "ride"), .ride)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "rim"), .sidestick)
    }

    func test_voiceTagBridge_unknownTagReturnsNil() {
        XCTAssertNil(AudioSampleCategory(voiceTag: "nonsense"))
        XCTAssertNil(AudioSampleCategory(voiceTag: ""))
    }

    func test_codable_roundTrip() throws {
        let encoded = try JSONEncoder().encode(AudioSampleCategory.kick)
        let decoded = try JSONDecoder().decode(AudioSampleCategory.self, from: encoded)
        XCTAssertEqual(decoded, .kick)
    }
}
